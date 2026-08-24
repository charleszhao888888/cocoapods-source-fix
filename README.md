# cocoapods-source-fix

CocoaPods 插件：在 `pod install` 后自动对指定 Pod 的源码/头文件做**文本替换**，用于修复第三方库的编译问题（表达式修复、私有头引入修复、任意文本替换等）。

> 原名 `cocoapods-header-fix` 已废弃——插件能力不止「头文件修复」（如 YYText 是表达式修复），故更名为 `cocoapods-source-fix`（源码文本替换修复）。

## 特点

- **Podfile 零改动**：通过 monkey-patch `Pod::Installer#install!`（与 `cocoapods-local-override` 相同机制，绕过 HooksManager 白名单），gem 以 `cocoapods-*` 前缀安装后由 CocoaPods 自动加载即生效，**无需在 Podfile 写 `plugin` 指令**
- **配置独立**：所有替换规则写在一个独立 YAML 文件中（默认 `Podfile 同目录/cocoapods-source-fix.yml`）
- **6 种目标定位**：相对目录 / 绝对目录 / 相对文件 / 绝对文件 / Pod 模块 / 全局
- **幂等**：重复执行 `pod install` 不重复破坏文件（内容无变化则跳过写文件）
- **安全**：写文件前 `chmod 0644`；文件不存在 / glob 无匹配静默跳过

## 安装与集成

### 方式一：Gemfile（推荐，项目用 `bundle exec pod install` 时）

在项目的 Gemfile 中加：

```ruby
gem 'cocoapods-source-fix', :path => '/path/to/cocoapods-source-fix'
```

然后 `bundle install && bundle exec pod install`。

### 方式二：gem 全局安装（项目直接用 `pod install` 时）

```bash
cd '/path/to/cocoapods-source-fix'
gem build cocoapods-source-fix.gemspec
gem install cocoapods-source-fix-0.1.0.gem
```

之后 `pod install` 自动生效。

## 配置

创建 `cocoapods-source-fix.yml` 放在 **Podfile 同目录**（或通过环境变量 `COCOAPODS_SOURCE_FIX_CONFIG` 指定路径）：

```yaml
rules:
  # Pod 模块：glob 相对该 Pod 目录
  - name: YYText 表达式修复
    pod: YYText
    glob: 'YYText/Component/YYTextLayout.m'
    pairs:
      - from: 'fabs(left - point.y) < fabs(right - point.y) < (right ? prev : next)'
        to:   '(fabs(left - point.y) < fabs(right - point.y)) == (right ? prev : next)'
      - from: 'fabs(left - point.x) < fabs(right - point.x) < (right ? prev : next)'
        to:   '(fabs(left - point.x) < fabs(right - point.x)) == (right ? prev : next)'

  # 相对 Podfile 的目录
  - dir: 'Pods/SomePod'
    glob: '**/*.{h,m}'
    from: 'OLD_TEXT'
    to: 'NEW_TEXT'

  # 绝对路径目录
  - dir: '/Users/xxx/Source/Pods/SomePod'
    glob: '**/*.m'
    from: 'OLD_TEXT'
    to: 'NEW_TEXT'

  # 相对 Podfile 的文件
  - file: 'Pods/SomePod/SomePod/Foo.m'
    from: 'OLD_TEXT'
    to: 'NEW_TEXT'

  # 绝对文件
  - file: '/Users/xxx/Source/Pods/SomePod/SomePod/Foo.m'
    from: 'OLD_TEXT'
    to: 'NEW_TEXT'

  # 不指定目标：全局替换（glob 相对 Podfile 目录）
  - glob: 'Pods/**/*.{h,m}'
    from: 'OLD_TEXT'
    to: 'NEW_TEXT'
```

完整可运行示例见 [config.example.yml](config.example.yml)。

### 规则字段

| 字段 | 必填 | 说明 |
|---|---|---|
| `name` | 否 | 日志标签，便于识别规则 |
| `pod` / `dir` / `file` | 六选一 | 目标定位；均不指定则为全局（glob 相对 Podfile 目录） |
| `glob` | 目录/全局必填 | 文件匹配模式；Pod 模块下相对 Pod 目录，目录/全局下相对目标目录 |
| `exclude` | 否 | 排除文件/目录，字符串或数组，glob 模式，基准与 `glob` 相同；`'xx/**'` 或 `'**'` 表示排除整棵目录树 |
| `from` / `to` | 至少一组 | 单组字面量替换（`regex: true` 时按正则） |
| `pairs` | 否 | 多组替换 `[{from, to, regex?}]` |
| `regex` | 否 | 默认 `false`（字面量替换，自动转义正则元字符）；`true` 时按正则替换 |
| `enabled` | 否 | 默认 `true`，可临时关闭某条规则 |

`exclude` 使用示例：

```yaml
- name: LFPhoneInfo 头引入方式修复
  pod: LFPhoneInfo
  glob: '**/*.{h,m,mm,swift}'
  from: '#import <LFPhoneDefine.h>'
  to:   '#import "LFPhoneDefine.h"'
  exclude:
    - 'LFPhoneInfo/LFPhoneInfo.h'   # 排除单个文件
    - 'LFPhoneInfo/Private/**'      # 排除整棵目录树
```

## 日志输出

日志统一走 `Pod::UI.puts`，格式参照 `cocoapods-user-defined-build-types` 插件（`🛠️ [cocoapods-source-fix] ...` 蓝色）。**不修复也会输出日志**，并区分原因：

```
🛠️ [cocoapods-source-fix] 使用配置文件：/path/to/cocoapods-source-fix.yml（3 条规则）
🛠️ [cocoapods-source-fix] patching source files...
🛠️ [cocoapods-source-fix]   processing rule: YYText 表达式修复
🛠️ [cocoapods-source-fix]     ✅ 已修复文件：/path/to/Pods/YYText/YYText/Component/YYTextLayout.m
🛠️ [cocoapods-source-fix]   processing rule: AFNetworking 私有头修复
🛠️ [cocoapods-source-fix]     ⏭️ 跳过（2 个文件内容已是最新，无需修复）
🛠️ [cocoapods-source-fix]   processing rule: 某条无匹配的规则
🛠️ [cocoapods-source-fix]     ⏭️ 跳过（无匹配文件）
🛠️ [cocoapods-source-fix] finished patching source files (1 fixed, 2 skipped)
```

各场景日志：

| 场景　　　　　　　　　　　　　　 | 日志　　　　　　　　　　　　　　　　　　　　　　　　　|
| ----------------------------------| -------------------------------------------------------|
| 修复了文件　　　　　　　　　　　 | `✅ 已修复文件：<path>`　　　　　　　　　　　　　　　　|
| 匹配到文件但内容已是最新（幂等） | `⏭️ 跳过（N 个文件内容已是最新，无需修复）`　　　　　　|
| 无文件匹配 glob　　　　　　　　　| `⏭️ 跳过（无匹配文件）`　　　　　　　　　　　　　　　　|
| 读取失败　　　　　　　　　　　　 | `⚠️ 读取失败：<path>`　　　　　　　　　　　　　　　　　|
| 结束汇总　　　　　　　　　　　　 | `finished patching source files (N fixed, M skipped)` |

### 详细日志（verbose）

默认只输出规则级汇总；配置 `verbose: true`（或环境变量 `COCOAPODS_SOURCE_FIX_VERBOSE=1`）后逐文件输出：

```
🛠️ [cocoapods-source-fix]     ⏭️ 已是最新：/path/to/Pods/YYText/YYText/Component/YYTextLayout.m
🛠️ [cocoapods-source-fix]     🚫 已排除：/path/to/Pods/LFPhoneInfo/LFPhoneInfo/Private/Secret.h
```

- 每个实际发生替换的文件：`✅ 已修复文件：<path>`
- 无匹配的规则：`⏭️ 跳过（无匹配）`
- 配置文件不存在时提示跳过，不中断安装

## 文档导航

| 文件 | 说明 |
|---|---|
| `REQUIREMENTS.md` | 需求梳理（背景 / 方案 / 验收标准） |
| `lib/` | 插件实现 |
| `config.example.yml` | 配置示例（覆盖 6 种目标定位） |
| `cocoapods-source-fix.gemspec` | gem 定义 |

## 验证

```bash
pod install            # 首次：看到 ✅ 已修复文件
pod install            # 再次：看到 ⏭️ 跳过（幂等验证）
```
