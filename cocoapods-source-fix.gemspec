require_relative 'lib/cocoapods-source-fix/version'

Gem::Specification.new do |s|
  s.name          = 'cocoapods-source-fix'
  s.version       = CocoapodsSourceFix::VERSION
  s.authors       = ['ZCW']
  # 注：git 未配置 user.email，且 rubygems 上已发布的 0.1.1 也未登记 email（None），故暂不设置
  # s.email = [...]
  s.summary       = 'CocoaPods plugin to apply text replacements to pod sources after pod install'
  s.description   = 'Automatically apply text replacements (expression fixes, private header import fixes, etc.) to Pod sources after `pod install`, configured via a standalone YAML file. No Podfile modification required.'
  s.homepage      = 'https://github.com/charleszhao888888/cocoapods-source-fix'
  s.license       = 'MIT'
  s.metadata      = {
    'source_code_uri' => 'https://github.com/charleszhao888888/cocoapods-source-fix',
    'homepage_uri'    => 'https://rubygems.org/gems/cocoapods-source-fix'
  }

  s.require_paths = ['lib']
  s.files         = Dir['lib/**/*.rb'] + %w[README.md config.example.yml LICENSE]

  s.required_ruby_version = '>= 2.6'
  s.add_dependency 'cocoapods', '~> 1.0', '>= 1.0.0'
end
