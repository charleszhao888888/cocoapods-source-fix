require_relative 'lib/cocoapods-source-fix/version'

Gem::Specification.new do |s|
  s.name          = 'cocoapods-source-fix'
  s.version       = CocoapodsSourceFix::VERSION
  s.authors       = ['ZCW']
  s.summary       = 'CocoaPods plugin to apply text replacements to pod sources after pod install'
  s.description   = 'Automatically apply text replacements (expression fixes, private header import fixes, etc.) to Pod sources after `pod install`, configured via a standalone YAML file. No Podfile modification required.'
  s.homepage      = 'https://github.com/charleszhao888888/cocoapods-source-fix'
  s.license       = 'MIT'

  s.require_paths = ['lib']
  s.files         = Dir['lib/**/*.rb'] + %w[README.md config.example.yml]

  s.required_ruby_version = '>= 2.6'
  s.add_dependency 'cocoapods', '>= 1.0.0'
end
