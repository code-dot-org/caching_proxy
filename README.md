# Caching Proxy

Configuration layer for several HTTP caching proxies.

This gem standardizes certain features of HTTP caching proxy configuration into a common,
document-based format shared across several backend implementations. This allows you to define advanced
caching behaviors that function the same across any backend, so you can mix and match caching proxies for specific environments while preserving similar behavior across them.

Caching proxies currently supported:

- Rack middleware (via [Rack::Cache](https://github.com/rtomayko/rack-cache))
- [Varnish Cache](https://varnish-cache.org/)
- [Amazon CloudFront](https://aws.amazon.com/cloudfront/)

Caching behaviors currently supported, configurable per host and per path:

- Filter individual HTTP headers and/or cookies, separately caching objects based on the value.
- Proxy requests to different origin servers.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'caching_proxy'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install caching_proxy

## Usage

```ruby
# Varnish VCL string
vcl = CachingProxy::Varnish.varnish(config)

# CloudFront::Distribution CloudFormation resource hash
cloudfront = CachingProxy::CloudFront.cloudfront(config)

# Rack Middleware object
app = ->(*) { [200, { 'Content-Type' => 'text/plain' }, ['app']] }
foo = ->(*) { [200, { 'Content-Type' => 'text/plain' }, ['foo']] }

cached_app = Rack::Builder.new do
  use CachingProxy::Rack,
      default: :my_backend,
      config: config,
      backends: {foo: foo}
  run app
end
```

## Config format

The `config` hash defines the application-specific cache configuration used by caching proxies.

Example:

```ruby
{
  foo: {
    origin: "foo-origin-environment.example.com",
    aliases: ['foo-environment.example.com'],
    behaviors: [
      {
        path: '/hello',
        headers: [],
        cookies: []
      }
    ],
    default: {
      headers: [],
      cookies: []
    }
  },
  bar: {
    origin: 'bar-origin-environment.example.com',
    aliases: ['bar-environment.example.com'],
    behaviors: [
      {
        path: %w[/hello /world],
        headers: [],
        cookies: []
      },
    ],
    default: {
      headers: [],
      cookies: []
    }
  },
}
```
The top-level Hash contains a set of backends with the following properties:

- `behaviors`: Array of behaviors. For a given HTTP request, `behaviors` is searched in-order
  until the first matching `path` is found. If no `path` matches the request, the `default` behavior is used.
  - `path`: Path string to match this behavior against.
    A single `*`-wildcard is permitted, used either as an extension (`/*.jpg`) or
    a path prefix (`/api/*`).
    - `path` can be a String or an Array. If it is an Array, a separate
      behavior will be generated for each element.
    - Paths match the CloudFront [path pattern](http://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/distribution-web-values-specify.html#DownloadDistValuesPathPattern)
      syntax, with additional restrictions:
      - `?` and `&` characters are not allowed.
      - Only a single `*` wildcard is allowed at the start or end of the path pattern.
  - `headers`: Cache objects based on additional HTTP request headers.
    To include all headers (which disables caching entirely for the path), pass `['*']`.
    To include no additional request headers in the cache key, pass `[]`.
    - Note: The cache key will always include the `Host` header by default.
  - `cookies`: Cache objects based on additional HTTP cookie keys.
    To include all cookies for the path, pass `'all'`.
    To strip all cookies for the path, pass `'none'`.
  - `proxy`: If specified, proxy all requests matching this path to the
    specified origin.
    - Note: paths are not rewritten, so a GET request
      to `myserver.example.com/here/abc` configured with the behavior
      `{path: '/here/*' proxy: 'myproxy' }` will proxy its request to
      `myproxy.example.com/here/abc`.
- `default`: Default behavior if no path patterns are matched.
  Uses the same syntax as `behaviors` except `path` is not required.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/caching_proxy.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
