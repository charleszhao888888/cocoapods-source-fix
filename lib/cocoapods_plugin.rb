# CocoaPods 插件发现入口
#
# CocoaPods 启动时自动扫描所有已安装 gem 中的 `cocoapods_plugin.rb` 并 require，
# 无需在 Podfile 中写 plugin 指令（与 cocoapods-local-override 相同机制）。
# 加载主入口，注册 :post_install hook。
require 'cocoapods-source-fix'
