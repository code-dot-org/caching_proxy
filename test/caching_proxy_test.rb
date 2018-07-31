# frozen_string_literal: true

require 'test_helper'
require 'rack/test'
require 'rack/builder'

class CachingProxyTest < Minitest::Test
  CONFIG = {
    dashboard: {
      origin: 'example.com',
      aliases: ['alias.example.com'],
      log: 'example-log.s3.amazonaws.com/prefix',
      behaviors: [
        {
          path: %w[/hello* /world*],
          headers: [],
          cookies: []
        },
        {
          path: '/s3_asset/*',
          headers: [],
          cookies: [],
          proxy: 's3_proxy'
        }
      ],
      default: {
        headers: [],
        cookies: []
      }
    },
    s3_proxy: {
      origin: 'example.s3.amazonaws.com/prefix'
    }
  }.freeze

  def test_version_number
    refute_nil ::CachingProxy::VERSION
  end

  def test_varnish
    refute_empty CachingProxy::Varnish.varnish(CONFIG)
  end

  def test_cloudfront
    require 'json'
    refute_empty JSON.pretty_generate(CachingProxy::CloudFront.cloudfront(CONFIG))
  end

  include Rack::Test::Methods

  def app
    Rack::Builder.new do
      use CachingProxy::Rack,
          default: :dashboard,
          config: CONFIG
      run ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['OK']] }
    end
  end

  def test_rack
    refute_empty get '/'
  end
end
