# cocoapods-source-fix 插件需求梳理

> 原名 `cocoapods-header-fix`。因插件能力不止「头文件修复」（如 YYText 表达式修复），更名 `cocoapods-source-fix`（对 Pod 源码做文本替换修复）。
> 本文档是**新会话**实现/维护本插件的唯一需求依据。

---

## 1. 背景与痛点

Dispatch 主工程此前在 `Podfile` 的 `post_install` 中**手写硬编码**了 3 类「对 Pods 目录文件的文本替换」，用于修复第三方库的编译问题：

1. YYText 表达式修复（2 处字符串替换）
2. AFNetworking 私有头引入修复（2 个文件）
3. LFPhoneInfo 头文件引入修复（目录遍历替换）

**痛点**：
- 逻辑散落在 Podfile 里，与业务配置耦合，每次 `pod install` 都执行但无法复用
- 换项目 / 换机器 / 多 Podfile 时无法复用
- 硬编码路径，库升级后容易失效
- 无法配置化（哪几个库、替换什么、替换成什么都是写死的）

**目标**：把「在 pod install 后对指定 Pod 的文件做文本替换」这一能力，抽成一个**标准 CocoaPods 插件**（gem），通过**独立配置文件**声明规则，无需改插件代码即可覆盖任意库的任意替换需求，且**无需修改 Podfile**。

---

## 2. 核心设计决策

### 2.1 插件形态
- **Gem 名称**：`cocoapods-source-fix`（`cocoapods-<name>` 前缀，CocoaPods 自动加载，**Podfile 无需写 `plugin` 指令**）
- **入口文件**：`lib/cocoapods-source-fix.rb`，注册 `Pod::HooksManager :post_install` hook
- **版本文件**：`lib/cocoapods-source-fix/version.rb`，`CocoapodsSourceFix::VERSION`

### 2.2 配置方式（独立配置文件，Podfile 零改动）
- **默认配置文件**：`<Podfile 目录>/cocoapods-source-fix.yml`
- **环境变量覆盖**：`COCOAPODS_SOURCE_FIX_CONFIG=/path/to/config.yml pod install`
- 配置文件不存在时静默跳过（不打扰正常安装）

### 2.3 规则目标定位（六选一，均不指定为全局）
| 方式 | 字段 | 路径基准 |
|---|---|---|
| Pod 模块 | `pod: 'YYText'` | `installer.sandbox.pod_dir(name)`，glob 相对该目录 |
| 相对目录 | `dir: 'Pods/SomePod'` | Podfile 目录 |
| 绝对目录 | `dir: '/abs/path'` | 绝对路径 |
| 相对文件 | `file: 'Pods/A/Foo.m'` | Podfile 目录 |
| 绝对文件 | `file: '/abs/path/Foo.m'` | 绝对路径 |
| 全局 | （无以上字段） | glob 相对 Podfile 目录（如 `Pods/**/*.{h,m}`） |

### 2.4 替换内容
- `from`/`to`：单组替换；`pairs: [{from, to, regex?}]`：多组替换
- 默认**字面量替换**（`Regexp.escape` 后 gsub，避免正则元字符误伤）
- `regex: true` 时按正则替换
- 其他字段：`name`（日志标签）、`enabled`（默认 true）

### 2.5 幂等性与健壮性
- **幂等**：`new_content == content` 则跳过写文件
- **只读判断**：文件不存在 / glob 无匹配静默跳过
- **权限**：写文件前 `FileUtils.chmod 0644`
- **日志**：统一走 `Pod::UI.puts`，格式参照 `cocoapods-user-defined-build-types`（`🔥 [cocoapods-source-fix] ...` 蓝色）；实际替换打印 `✅ 已修复文件：<path>`；规则无匹配打印 `⏭️ 跳过（无匹配）`；结束打印 `finished patching source files (N file(s) fixed)`
- **编码**：`File.read` 直接读（与现有行为一致，UTF-8 兼容）

---

## 3. 需迁移的现有规则（写入独立配置文件）

### 3.1 YYText（表达式修复）
```yaml
- name: YYText 表达式修复
  pod: YYText
  glob: 'YYText/Component/YYTextLayout.m'
  pairs:
    - from: 'fabs(left - point.y) < fabs(right - point.y) < (right ? prev : next)'
      to:   '(fabs(left - point.y) < fabs(right - point.y)) == (right ? prev : next)'
    - from: 'fabs(left - point.x) < fabs(right - point.x) < (right ? prev : next)'
      to:   '(fabs(left - point.x) < fabs(right - point.x)) == (right ? prev : next)'
```

### 3.2 AFNetworking（私有头修复）
```yaml
- name: AFNetworking 私有头修复
  pod: AFNetworking
  glob: 'AFNetworking/AF{NetworkReachabilityManager,HTTPSessionManager}.m'
  from: '#import <netinet6/in6.h>'
  to:   '#include <sys/socket.h>'
```

### 3.3 LFPhoneInfo（头文件引入方式修复）
```yaml
- name: LFPhoneInfo 头引入方式修复
  pod: LFPhoneInfo
  glob: '**/*.{h,m,mm,swift}'
  from: '#import <LFPhoneDefine.h>'
  to:   '#import "LFPhoneDefine.h"'
```

> 迁移完成后，Podfile `post_install` 中对应三段硬编码代码可删除（保留 DEVELOPMENT_TEAM 等无关逻辑）。**当前阶段为验证插件，暂不改动 Podfile。**

---

## 4. 与项目集成方式

### 4.1 开发调试
- Gemfile 方式：`gem 'cocoapods-source-fix', :path => '...'` + `bundle exec pod install`
- 全局安装方式：`gem build` + `gem install`，之后直接 `pod install`

### 4.2 验证步骤（必须做）
1. `pod install` 正常完成，无 error
2. 终端能看到 `✅ 已修复文件：...` 且覆盖 YYText / AFNetworking / LFPhoneInfo 三类
3. 检查产物：
   - `Pods/LFPhoneInfo/LFPhoneInfo/UIDevice+LFDeviceInfo.h` 第 13 行为 `#import "LFPhoneDefine.h"`
   - `Pods/AFNetworking/AFNetworking/AFHTTPSessionManager.m` 含 `#include <sys/socket.h>`
   - `Pods/YYText/YYText/Component/YYTextLayout.m` 含 `== (right ? prev : next)`
4. **连续跑两次 `pod install`**：第二次日志应显示跳过（幂等性验证）
5. Xcode 编译通过（重点：不再报 LFPhoneInfo 的 `LFPhoneDefine.h` 找不到等）

### 4.3 迁移收尾
- 验证通过后，删除 Podfile `post_install` 中 YYText / AFNetworking / LFPhoneInfo 三段替换代码
- 保留 `post_install` 中与替换无关的逻辑（DEVELOPMENT_TEAM 设置、预编译宏等）

---

## 5. 任务清单

- [x] 1. 创建 gem 骨架：`cocoapods-source-fix.gemspec`、`Gemfile`、`lib/cocoapods-source-fix.rb`、`lib/cocoapods-source-fix/version.rb`
- [x] 2. 实现核心替换逻辑（HooksManager :post_install）：
      - 独立配置文件解析（默认 Podfile 同目录 / 环境变量覆盖）
      - 6 种目标定位：pod / dir(相对) / dir(绝对) / file(相对) / file(绝对) / 全局
      - 单组 `from/to` 与多组 `pairs`，字面量 + 正则（`regex: true`）
      - 幂等 + 日志输出 + chmod 0644
- [ ] 3. 编写测试（可选但推荐）：用 fixture 目录模拟 Pods 结构跑替换逻辑，断言替换结果与幂等性
- [ ] 4. 与 Dispatch 工程集成（4.1），跑 `pod install` 验证（4.2 全部步骤）
- [ ] 5. 迁移 Podfile：删除 post_install 中三段替换代码（验证通过后执行，4.3）
- [ ] 6. 最后回归：`pod install` 连续 2 次 + Xcode 编译

---

## 6. 参考代码

- CocoaPods 插件官方文档：https://guides.cocoapods.org/plugins/creating-a-cocoapods-plugin.html
