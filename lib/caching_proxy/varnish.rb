# frozen_string_literal: true

require 'erb'

module CachingProxy
  module Varnish
    # VCL string to create or update a Vary header field with the provided Vary header.
    def self.set_vary(header, resp)
      # Matches a Vary header field delimiter.
      sep = '(\\s|,|^|$)'
      <<~VCL
        if (!#{resp}.http.Vary) {
          set #{resp}.http.Vary = "#{header}";
        } elseif (#{resp}.http.Vary !~ "#{sep}#{header}#{sep}") {
          set #{resp}.http.Vary = #{resp}.http.Vary + ", #{header}";
        }
      VCL
    end

    # VCL string to set the appropriate Vary header fields based on the provided cache behavior.
    # Whitelisted headers are added to Vary directly.
    # Whitelisted cookies are added to Vary via their extracted X-COOKIE headers.
    def self.process_vary(behavior, *)
      behavior[:headers].map do |header|
        set_vary(header, 'beresp')
      end.join +
        if behavior[:cookies] == 'all'
          set_vary('Cookie', 'beresp')
        elsif behavior[:cookies] != 'none'
          behavior[:cookies].map do |cookie|
            set_vary("X-COOKIE-#{cookie}", 'beresp')
          end.join
        end
    end

    # VCL string to extract a cookie into an internal X-COOKIE HTTP header.
    def self.extract_cookie(cookie)
      <<~VCL
        if(cookie.isset("#{cookie}")) {
          set req.http.X-COOKIE-#{cookie} = cookie.get("#{cookie}");
        }
      VCL
    end

    # Returns a regex-conditional string fragment based on the provided behavior.
    # In the 'proxy' section, ignore extension-based behaviors (e.g., *.png).
    def self.paths_to_regex(path_config, req = 'req')
      paths = CachingProxy.normalize_paths(path_config)
      vcl_or(paths.map { |path| %(#{req}.url ~ "#{path}") })
    end

    def self.process_request(behavior, *)
      filter_cookies(behavior[:cookies]) +
        filter_headers(behavior[:headers])
    end

    def self.filter_cookies(cookies)
      case cookies
      when 'all'
        '# Allow all request cookies.'
      when 'none'
        'cookie.filter_except("NO_CACHE");'
      else
        cookies.map(&method(:extract_cookie)).join +
          %[cookie.filter_except("#{cookies.join(',')}");]
      end
    end

    def self.filter_headers(headers)
      REMOVED_HEADERS.map do |remove_header|
        name, value = remove_header.split ':'
        next if headers.include? name
        if value.nil?
          "\nunset req.http.#{name};"
        else
          %(\nset req.http.#{name} = "#{value}";)
        end
      end.join
    end

    def self.unset_header(header)
      <<~VCL
        if(req.http.#{header}) { unset req.http.#{header}; }
      VCL
    end

    # Returns the cookie-filter string for a given 'cookies' behavior.
    def self.process_response(behavior, *)
      if behavior[:cookies] == 'none'
        'unset beresp.http.set-cookie;'
      else
        '# Allow set-cookie responses.'
      end
    end

    # Set the backend hint for a given proxy.
    def self.process_proxy(behavior, behavior_backend, config)
      backend = (behavior[:proxy] || behavior_backend).to_sym
      raise ArgumentError, "Invalid proxy: #{backend}" unless config.key?(backend)
      "set req.backend_hint = director_#{backend}.backend();" +
        if backend != behavior_backend
          cb = config[backend]
          %(\nset req.http.host = "#{cb[:aliases]&.first || cb[:origin]}";)
        end.to_s
    end

    # Returns the hostname-matching VCL expression for the backend provided.
    def self.if_backend(aliases, req)
      hosts = aliases.each do |host|
        %(#{req}.http.host == "#{host}")
      end
      vcl_or(hosts)
    end

    # Generate an "if(){} else if {} else {}" string from an array of items, conditional Proc, and a block.
    def self.if_else(items, cond)
      items.each_with_index.map do |item, i|
        condition = cond.call(item)
        return yield(item) if i == 1 && condition.nil? && items.one?
        next if condition.to_s == 'false'
        "#{i != 0 ? 'else ' : ''}#{condition && "if (#{condition}) "}{\n" +
          yield(item).lines.map { |line| '  ' + line }.join << "\n} "
      end.join.slice(-1)
    end

    # Generate a boolean AND expression from an array of expressions.
    def self.vcl_and(expressions)
      expressions.empty? ? 'false' : expressions.join(" &&\n")
    end

    # Generate a boolean OR expression from an array of expressions.
    def self.vcl_or(expressions)
      expressions.empty? ? 'false' : expressions.join(" ||\n")
    end

    # Generate a VCL string for all behaviors in the provided config,
    # by executing the given block on each behavior.
    def self.setup_behavior(config, req = 'req')
      backend_condition = lambda do |backend|
        if_backend(config[backend][:aliases], req)
      end
      hosts = config.select { |_, backend_config| backend_config[:default] }.keys
      if_else(hosts, backend_condition) do |backend|
        backend_config = config[backend]
        configs = backend_config[:behaviors] + [backend_config[:default]]
        path_condition = lambda do |behavior|
          behavior[:path] ? paths_to_regex(behavior[:path], req) : nil
        end
        if_else(configs, path_condition) do |behavior|
          yield behavior, backend, config
        end
      end
    end

    def self.varnish(config)
      local_binding = binding
      local_binding.local_variable_set(:backends, config)
      filename = File.join(__dir__, 'varnish/varnish.vcl.erb')
      ERB.new(File.read(filename), nil, '-')
         .tap { |x| x.filename = filename }
         .result(local_binding)
    end
  end
end
