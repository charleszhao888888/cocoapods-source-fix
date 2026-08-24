require 'yaml'
require 'cocoapods-source-fix/rule'

module CocoapodsSourceFix
  # 读取独立配置文件（默认 <Podfile 目录>/cocoapods-source-fix.yml）
  class Configuration
    CONFIG_FILE_NAME = 'cocoapods-source-fix.yml'
    ENV_KEY = 'COCOAPODS_SOURCE_FIX_CONFIG'
    ENV_VERBOSE_KEY = 'COCOAPODS_SOURCE_FIX_VERBOSE'

    attr_reader :path, :rules, :verbose

    # 定位配置文件：环境变量优先，其次 Podfile 同目录默认文件名
    def self.locate(podfile_dir)
      env_path = ENV[ENV_KEY]
      return Pathname.new(env_path) if env_path && File.file?(env_path)

      default = File.join(podfile_dir, CONFIG_FILE_NAME)
      File.file?(default) ? Pathname.new(default) : nil
    end

    def initialize(path, podfile_dir:)
      @path = path
      @data = YAML.load_file(path) || {}
      @rules = Array(@data['rules']).map { |raw| Rule.new(raw, base_dir: podfile_dir) }
      @verbose = parse_verbose
    end

    private

    # verbose 优先级：环境变量 > 配置文件 > 默认 false
    def parse_verbose
      env = ENV[ENV_VERBOSE_KEY]
      return %w[1 true yes on].include?(env.downcase) if env && !env.empty?

      @data['verbose'] == true
    end
  end
end
