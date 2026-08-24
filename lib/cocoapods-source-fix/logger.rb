module CocoapodsSourceFix
  PLUGIN_NAME = 'cocoapods-source-fix'

  # 统一日志出口，参照 cocoapods-user-defined-build-types 风格：
  #   Pod::UI.puts "🛠️ [cocoapods-user-defined-build-types] patching build types...".blue
  module Logger
    def self.info(msg)
      line = "🛠️ [#{PLUGIN_NAME}] #{msg}"
      if defined?(Pod) && defined?(Pod::UI)
        begin
          Pod::UI.puts line.blue
        rescue StandardError
          Pod::UI.puts line
        end
      else
        Kernel.puts line
      end
    end
  end
end
