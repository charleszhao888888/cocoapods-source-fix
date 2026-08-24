require 'ostruct'
require 'cocoapods-source-fix/version'
require 'cocoapods-source-fix/logger'
require 'cocoapods-source-fix/configuration'
require 'cocoapods-source-fix/runner'

module CocoapodsSourceFix
  class << self
    # install! 完成后执行源码替换（加载即生效，无需 Podfile 声明 plugin）
    def run_post_install(installer)
      podfile_dir = podfile_dir_from(installer)
      config_path = Configuration.locate(podfile_dir)
      unless config_path
        Logger.info "未找到配置文件（#{Configuration::ENV_KEY} 或 #{Configuration::CONFIG_FILE_NAME}），跳过替换"
        return
      end

      config = Configuration.new(config_path, podfile_dir: podfile_dir)
      Logger.info "使用配置文件：#{config_path}（#{config.rules.size} 条规则）"
      # Runner 依赖 sandbox 定位 pod 目录，从 installer 实例提取并包装成轻量 context
      context = OpenStruct.new(
        sandbox: installer.sandbox,
        sandbox_root: installer.sandbox.root.to_s
      )
      Runner.new(context, config, podfile_dir: podfile_dir).run
    end

    # 安装 monkey-patch：拦截 Pod::Installer#install!，在其执行完成后运行替换。
    # 与 cocoapods-local-override 相同的机制——绕过 HooksManager 的 whitelist
    # （whitelist 只放行 Podfile 中 plugin 声明的 hook），因此无需修改 Podfile。
    def apply_installer_hook!
      return if @installer_hook_applied
      @installer_hook_applied = true

      Pod::Installer.class_eval do
        unless method_defined?(:source_fix_original_install!)
          alias_method :source_fix_original_install!, :install!

          define_method :install! do |*args|
            source_fix_original_install!(*args)
            CocoapodsSourceFix.run_post_install(self)
          end
        end
      end
    end

    private

    def podfile_dir_from(installer)
      # 1. 全局 Pod::Config 中已加载的 Podfile（最可靠，含 defined_in_file）
      if defined?(Pod::Config) && Pod::Config.instance.respond_to?(:podfile)
        pf = Pod::Config.instance.podfile
        if pf && pf.respond_to?(:defined_in_file) && pf.defined_in_file
          return File.dirname(pf.defined_in_file.to_s)
        end
      end
      # 2. 兜底：sandbox.root（默认 <Podfile 目录>/Pods）的上级目录
      if installer.respond_to?(:sandbox) && installer.sandbox &&
         installer.sandbox.respond_to?(:root) && installer.sandbox.root
        return File.dirname(installer.sandbox.root.to_s)
      end
      # 3. 最终兜底：当前工作目录
      Dir.pwd
    end
  end
end

# 说明：CocoaPods 启动时自动 require gem 内的 lib/cocoapods_plugin.rb（无需 Podfile
# 声明），此处直接 monkey-patch Pod::Installer#install!，加载即生效。
CocoapodsSourceFix.apply_installer_hook!
