lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'caching_proxy/version'

Gem::Specification.new do |spec|
  spec.name          = 'caching_proxy'
  spec.version       = CachingProxy::VERSION
  spec.authors       = ['Will Jordan']
  spec.email         = ['will@code.org']

  spec.summary       = 'Configuration layer for several HTTP caching proxies.'
  spec.description   = 'Configuration layer for several HTTP caching proxies.'
  spec.homepage      = 'https://github.com/code-dot-org/caching_proxy'
  spec.license       = 'MIT'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise 'RubyGems 2.0 or newer is required to protect against ' \
      'public gem pushes.'
  end

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'activesupport'
  spec.add_dependency 'rack'
  spec.add_dependency 'rack-cache'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'minitest'
  spec.add_development_dependency 'rack-test'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'simplecov'

  spec.required_ruby_version = '>= 2.5.0'
end
