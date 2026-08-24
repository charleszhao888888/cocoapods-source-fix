# cocoapods-source-fix 插件需求梳理

> 本文档记录插件的背景、方案与验收标准，是维护插件的依据。

---

## 1. 背景与痛点

某 iOS 主工程此前在 `Podfile` 的 `post_install` 中**手写硬编码**了 3 类「对 Pods 目录文件的文本替换」，用于修复第三方库的编译问题，例如：

1. **表达式优先级修复**（2 处字符串替换）：C 语言中 `a < b < c` 实际按 `(a < b) < c` 求值，比较链结果错误，需补括号：

   ```ruby
   # Podfile post_install 中的硬编码写法
   file = File.join(sandbox_root, 'Pods/SomePod/SomePod/Component/SomeView.m')
   text = File.read(file)
   text.gsub!('a < b < c', '(a < b) < c')
   File.write(file, text)
   ```

2. **私有头引入修复**（2 个文件）：`#import <netinet6/in6.h>` 编译报找不到，需改为 `#include <sys/socket.h>`：

   ```ruby
   %w[SomeManager.m SomeSession.m].each do |name|
     file = File.join(sandbox_root, "Pods/SomePod/SomePod/#{name}")
     text = File.read(file)
     text.gsub!('#import <netinet6/in6.h>', '#include <sys/socket.h>')
     File.write(file, text)
   end
   ```

3. **头文件引入方式修复**（目录遍历替换）：`#import <SomeDefine.h>` 在编译时找不到，需改为 `#import "SomeDefine.h"` 相对引入：

   ```ruby
   Dir.glob(File.join(sandbox_root, 'Pods/SomePod/**/*.{h,m}')).each do |file|
     text = File.read(file)
     if text.include?('#import <SomeDefine.h>')
       text.gsub!('#import <SomeDefine.h>', '#import "SomeDefine.h"')
       File.write(file, text)
     end
   end
   ```

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
| Pod 模块 | `pod: 'SomePod'` | `installer.sandbox.pod_dir(name)`，glob 相对该目录 |
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
- **日志**：统一走 `Pod::UI.puts`，格式参照 `cocoapods-user-defined-build-types`（`🛠️ [cocoapods-source-fix] ...` 蓝色）；实际替换打印 `✅ 已修复文件：<path>`；规则无匹配打印 `⏭️ 跳过（无匹配）`；结束打印 `finished patching source files (N file(s) fixed)`
- **编码**：`File.read` 直接读（与现有行为一致，UTF-8 兼容）

---

## 3. 配置示例（写入独立配置文件）

### 3.1 表达式优先级修复（单文件多组替换）
```yaml
- name: 表达式优先级修复
  pod: SomePod
  glob: 'SomePod/Component/SomeView.m'
  pairs:
    - from: 'a < b < c'
      to:   '(a < b) < c'
    - from: 'x < y < z'
      to:   '(x < y) < z'
```

### 3.2 私有头引入修复（多文件 glob）
```yaml
- name: 私有头引入修复
  pod: SomePod
  glob: 'SomePod/Some{Manager,Session}.m'
  from: '#import <netinet6/in6.h>'
  to:   '#include <sys/socket.h>'
```

### 3.3 头文件引入方式修复（目录遍历）
```yaml
- name: 头文件引入方式修复
  pod: SomePod
  glob: '**/*.{h,m,mm,swift}'
  from: '#import <SomeDefine.h>'
  to:   '#import "SomeDefine.h"'
```

> 迁移完成后，Podfile `post_install` 中对应三段硬编码代码可删除（保留 DEVELOPMENT_TEAM 等无关逻辑）。**当前阶段为验证插件，暂不改动 Podfile。**

---

## 4. 与项目集成方式

### 4.1 开发调试
- Gemfile 方式：`gem 'cocoapods-source-fix', :path => '...'` + `bundle exec pod install`
- 全局安装方式：`gem build` + `gem install`，之后直接 `pod install`

### 4.2 验证步骤（必须做）
1. `pod install` 正常完成，无 error
2. 终端能看到 `✅ 已修复文件：...` 且覆盖三类修复
3. 检查产物：
   - `Pods/SomePod/SomePod/SomeView.h` 第 13 行为 `#import "SomeDefine.h"`
   - `Pods/SomePod/SomePod/SomeManager.m` 含 `#include <sys/socket.h>`
   - `Pods/SomePod/SomePod/Component/SomeView.m` 含 `(a < b) < c`
4. **连续跑两次 `pod install`**：第二次日志应显示跳过（幂等性验证）
5. Xcode 编译通过（重点：不再报 `SomeDefine.h` 找不到等）

### 4.3 迁移收尾
- 验证通过后，删除 Podfile `post_install` 中三段替换代码
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
- [ ] 4. 与目标主工程集成（4.1），跑 `pod install` 验证（4.2 全部步骤）
- [ ] 5. 迁移 Podfile：删除 post_install 中三段替换代码（验证通过后执行，4.3）
- [ ] 6. 最后回归：`pod install` 连续 2 次 + Xcode 编译

---

## 6. 参考代码

- CocoaPods 插件官方文档：https://guides.cocoapods.org/plugins/creating-a-cocoapods-plugin.html
