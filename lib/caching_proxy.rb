# frozen_string_literal: true

module CachingProxy
  autoload :VERSION, 'caching_proxy/version'
  autoload :Varnish, 'caching_proxy/varnish'
  autoload :Rack, 'caching_proxy/rack'
  autoload :CloudFront, 'caching_proxy/cloudfront'

  # Ref: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/RequestAndResponseBehaviorCustomOrigin.html#RequestCustomHTTPMethods
  ALLOWED_METHODS = %w[
    DELETE
    GET
    HEAD
    OPTIONS
    PATCH
    POST
    PUT
  ].freeze

  CACHED_METHODS = %w[
    HEAD
    GET
    OPTIONS
  ].freeze

  # CloudFront removes these headers by default.
  # Simulate similar behavior, with optional defaults.
  # Ref: http://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/RequestAndResponseBehaviorCustomOrigin.html#request-custom-headers-behavior
  REMOVED_HEADERS = %w[
    Accept
    Accept-Charset
    Accept-Language:en-US
    Referer
    User-Agent:Cached-Request
  ].freeze

  # Generic (PCRE) regex fragment for an optional query part of a URL
  # followed by end-of-string anchor.
  END_URL_REGEX = '(\\?.*)?$'

  # The maximum length of a path pattern is 255 characters.
  # The value can contain any of the following characters:
  # A-Z, a-z (case sensitive, so the path pattern /*.jpg doesn't apply to the file /LOGO.JPG.)
  # 0-9
  # _ - . $ / ~ " ' @ : +
  #
  # The following characters are allowed in CloudFront path patterns, but
  # are not allowed in our configuration format to reduce complexity:
  # * (exactly one wildcard required, either at the start or end of the path)
  # ? (No 1-character wildcards allowed)
  # &, passed and returned as &amp;
  def self.valid_path?(path)
    # Maximum length
    return false if path.length > 255
    # Valid characters allowed
    ch = %r{[A-Za-z0-9_\-.$/~"'@:+]*}
    # Require leading slash, maximum one wildcard allowed at start or end
    !path.match(%r{^/( \*#{ch} | #{ch}\* | #{ch} )$}x).nil?
  end

  # Takes an array of path-patterns as input, validating and normalizing
  # them for use within a generic (PCRE) regular expression.
  # Returns an array of path-matching regular expression strings.
  def self.normalize_paths(paths)
    paths = [paths] unless paths.is_a?(Array)
    paths.map(&:dup).map do |path|
      raise ArgumentError, "Invalid path: #{path}" unless valid_path?(path)
      # Strip leading slash from extension path
      path.gsub!(%r{^/(?=\*.)}, '')
      # Escape some valid special characters
      path.gsub!(/[.+$"]/) { |s| '\\' + s }
      # Replace * wildcards with .* regex fragment
      path.gsub!(/\*/, '.*')
      "^#{path}#{END_URL_REGEX}"
    end
  end

  # Evaluate the provided path against the provided config,
  # returning the first matched behavior.
  def self.behavior_for_path(behaviors, path)
    behaviors.detect do |behavior|
      paths = behavior[:path]
      next true unless paths
      normalize_paths(paths).any? { |p| path.match p }
    end
  end
end
