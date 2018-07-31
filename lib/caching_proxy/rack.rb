# frozen_string_literal: true

require 'active_support/core_ext/hash/slice'
require 'rack/response'
require 'rack/builder'
require 'rack/cache'

module CachingProxy
  # Rack middleware that filters cookies and headers based on cache behaviors.
  # Behaviors are defined in the provided config hash.
  module Rack
    # Builds the proxy middleware.
    # @param default_app [Object] default upstream Rack middleware chain
    # @param default [String] backend id matching the upstream middleware.
    # @param config [Hash] full http cache configuration.
    # @param backends [Hash] maps other backend IDs to alternate Rack apps.
    def self.new(default_app, default:, config:, backends: {})
      backend_apps = { default => default_app }.merge(backends).map do |backend_id, app|
        wrapped_app = ::Rack::Builder.new do
          backend = config[backend_id]
          use Downstream, backend
          use ::Rack::Cache, ignore_headers: []
          run Upstream.new(app, backend)
        end
        [backend_id, wrapped_app]
      end.to_h
      HostPicker.new(backend_apps, default, config)
    end

    # Pass request to a specific backend app depending on Host header.
    class HostPicker
      def initialize(backend_apps, default_id, config)
        @backend_apps = backend_apps
        @default_id = default_id
        @config = config
      end

      def call(env)
        request = ::Rack::Request.new(env)
        path = request.path

        # Match against aliases of each backend.
        backend = @config.find do |_, backend_config|
          (backend_config[:aliases] || []).any? { |host| host.include? request.host }
        end&.first || @default_id

        # Process HTTP-cache `proxy` values for path-specific behavior.
        config = @config[backend][:behaviors] + [@config[backend][:default]]
        behavior = CachingProxy.behavior_for_path(config, path)
        if behavior[:proxy]
          backend = behavior[:proxy]
          env[::Rack::HTTP_HOST] = behavior[:aliases].first
        end

        app = @backend_apps[backend]
        app.call(env)
      end
    end

    # Downstream middleware filters unwanted HTTP request headers and cookies,
    # extracting cookies into HTTP headers before the request reaches the cache.
    class Downstream
      attr_reader :config

      def initialize(app, config)
        @app = app
        @config = config
      end

      def call(env)
        unless ALLOWED_METHODS.include?(env[::Rack::REQUEST_METHOD].upcase)
          return [403, {}, ['Unsupported method.']]
        end
        request = ::Rack::Request.new(env)
        path = request.path
        behavior = CachingProxy.behavior_for_path((config[:behaviors] + [config[:default]]), path)

        # Filter whitelisted request headers.
        headers = behavior[:headers]
        REMOVED_HEADERS.each do |remove_header|
          name, value = remove_header.split ':'
          next if headers.include? name
          http_header = "HTTP_#{name.upcase.tr('-', '_')}"
          if value.nil?
            env.delete http_header
          else
            env[http_header] = value
          end
        end

        cookies = behavior[:cookies]
        case cookies
        when 'all'
          # Pass all cookies.
          @app.call(env)
        when 'none'
          # Strip all cookies
          env.delete ::Rack::HTTP_COOKIE
          status, headers, body = @app.call(env)
          headers.delete ::Rack::SET_COOKIE
          [status, headers, body]
        else
          # Strip all request cookies not in whitelist.
          # Extract whitelisted cookies to X-COOKIE-* request headers.
          request_cookies = request.cookies
          request_cookies.slice!(*cookies)
          cookie_str = request_cookies.map do |key, value|
            env_key = "HTTP_X_COOKIE_#{key.upcase.tr('-', '_')}"
            env[env_key] = value
            ::Rack::Utils.escape(key) + '=' + ::Rack::Utils.escape(value)
          end.join('; ') + ';'
          env[::Rack::HTTP_COOKIE] = cookie_str
          @app.call(env)
        end
      end
    end

    # Upstream middleware adds Vary headers to the HTTP response
    # before the response reaches the cache.
    class Upstream
      attr_reader :config

      def initialize(app, config)
        @app = app
        @config = config
      end

      def call(env)
        request = ::Rack::Request.new(env)
        path     = request.path
        behavior = CachingProxy.behavior_for_path((config[:behaviors] + [config[:default]]), path)

        status, headers, body = @app.call(env)
        response = ::Rack::Response.new(body, status, headers)

        (behavior[:headers] + %w[host]).each do |header|
          response.add_header('Vary', header)
        end

        cookies = behavior[:cookies]
        if cookies == 'all'
          response.add_header 'Vary', 'Cookie'
        elsif cookies != 'none'
          # Add "Vary: X-COOKIE-*" to the response for each whitelisted cookie.
          request_cookies = request.cookies
          request_cookies.slice!(*cookies)
          request_cookies.keys.each do |key|
            response.add_header 'Vary', "X-COOKIE-#{key.tr('_', '-')}"
          end
        end
        response.finish
      end
    end
  end
end
