# frozen_string_literal: true

module CachingProxy
  module CloudFront
    # List from: http://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/HTTPStatusCodes.html#HTTPStatusCodes-cached-errors
    ERROR_CODES = [400, 403, 404, 405, 414, 500, 501, 502, 503, 504].freeze

    # Configure CloudFront to forward these headers for S3 origins.
    S3_FORWARD_HEADERS = %w[
      Access-Control-Request-Headers
      Access-Control-Request-Method
      Origin
    ].freeze

    S3_SUFFIX = '.s3.amazonaws.com'

    # Returns a CloudFront DistributionConfig in CloudFormation format.
    def self.distribution_config(config, id)
      backend_config = config[id]
      return nil unless backend_config[:default]
      behaviors = backend_config[:behaviors].map do |behavior|
        paths = behavior[:path]
        paths = [paths] unless paths.is_a? Array
        CachingProxy.normalize_paths paths
        paths.map do |path|
          cache_behavior(id, behavior, path)
        end
      end.flatten

      {
        Aliases: backend_config[:aliases] || [],
        CacheBehaviors: behaviors,
        Comment: '',
        CustomErrorResponses: ERROR_CODES.map do |error|
          {
            ErrorCachingMinTTL: 0,
            ErrorCode: error
          }
        end,
        DefaultCacheBehavior: cache_behavior(id, backend_config[:default]),
        DefaultRootObject: '',
        Enabled: true,
        Origins: origins(config),
        ViewerCertificate: backend_config[:ssl_cert] || {
          CloudFrontDefaultCertificate: true,
          MinimumProtocolVersion: 'TLSv1' # accepts SSLv3, TLSv1
        },
        HttpVersion: 'http2'
      }.tap do |hash|
        if (log = backend_config[:log])
          log_uri = URI.parse(log)
          hash[:Logging] = {
            Bucket: log_uri.host,
            Prefix: log_uri.path,
            IncludeCookies: false
          }
        end
      end
    end

    def self.origins(config)
      config.map do |id, backend_config|
        origin_uri = URI.parse backend_config[:origin]
        origin_uri = URI.parse("//#{origin_uri}") if origin_uri.host.nil?

        {
          Id: id,
          DomainName: origin_uri.host,
          OriginPath: origin_uri.path
        }.tap do |origin|
          if origin_uri.host.end_with?(S3_SUFFIX)
            origin[:S3OriginConfig] = {
              OriginAccessIdentity: ''
            }
          else
            origin[:CustomOriginConfig] = {
              OriginSSLProtocols: %w[TLSv1.2 TLSv1.1]
            }.tap do |custom|
              case origin_uri.scheme
              when 'http'
                custom[:OriginProtocolPolicy] = 'http-only'
                custom[:HTTPPort] = origin_uri.port
              when 'https'
                custom[:OriginProtocolPolicy] = 'https-only'
                custom[:HTTPSPort] = origin_uri.port
              else
                custom[:OriginProtocolPolicy] = 'match-viewer'
              end
            end
          end
        end
      end
    end

    # Returns a CloudFront CacheBehavior Hash for the provided behavior config.
    def self.cache_behavior(id, behavior_config, path = nil)
      headers = behavior_config[:headers] + %w[Host CloudFront-Forwarded-Proto]
      cookie_config = behavior_config[:cookies].is_a?(Array) ?
        {
          Forward: 'whitelist',
          WhitelistedNames: behavior_config[:cookies]
        } :
        {
          Forward: behavior_config[:cookies]
        }

      {
        AllowedMethods: ALLOWED_METHODS,
        CachedMethods: CACHED_METHODS,
        Compress: true,
        DefaultTTL: 0,
        ForwardedValues: {
          Cookies: cookie_config,
          # Always include Host and CloudFront-Forwarded-Proto headers in cache key.
          Headers: headers,
          QueryString: true
        },
        MinTTL: 0,
        TargetOriginId: behavior_config[:proxy] || id,
        ViewerProtocolPolicy: 'redirect-to-https'
      }.tap do |behavior|
        behavior[:PathPattern] = path if path
      end
    end

    def self.cloudfront(config)
      config.keys.map do |id|
        [id, distribution_config(config, id)]
      end.to_h.compact
    end
  end
end
