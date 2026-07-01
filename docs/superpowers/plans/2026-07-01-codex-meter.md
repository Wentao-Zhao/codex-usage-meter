# CodexMeter 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 构建一个低资源 macOS 状态栏应用，从本机 Codex JSONL 增量统计 token，并展示五小时/周额度、倒计时和趋势折线。

**架构：** `CodexMeterCore` 负责无 UI 的解析、增量、分桶、额度策略和索引模型；`CodexMeter` 使用后台 `UsageService` 增量读取日志，通过不可变快照驱动 AppKit 状态栏与浮层。首次后台建索引，之后由 FSEvents 与五分钟对账触发增量刷新。

**技术栈：** Swift 5.9、AppKit、Foundation、DispatchSource、ServiceManagement `SMAppService`、Swift Package Manager、ad-hoc codesign。

**版本控制说明：** 当前项目父目录不是 Git 仓库，因此计划中的阶段检查以测试和构建结果代替 commit；不擅自初始化仓库。

---

## 文件结构

- `Package.swift`：SwiftPM 产品与 Core/App/LogicTests 三个 target。
- `Sources/CodexMeterCore/UsageModels.swift`：领域事件、额度、快照、颜色与索引模型。
- `Sources/CodexMeterCore/TokenEventParser.swift`：解析单条 `token_count` JSONL。
- `Sources/CodexMeterCore/SessionUsageAccumulator.swift`：累计 token 转增量并写入会话桶。
- `Sources/CodexMeterCore/UsageBuckets.swift`：时区分桶、周/月序列和数值格式化。
- `Sources/CodexMeterCore/RateLimitPolicy.swift`：剩余比例、过期、倒计时和颜色阈值。
- `Sources/CodexMeterCore/UsageIndex.swift`：索引编码、解码、会话去重与汇总快照。
- `Sources/CodexMeterCore/JSONLTokenScanner.swift`：从字节偏移流式读取候选行。
- `Sources/CodexMeterCore/UsageLogIndexer.swift`：发现日志、移动去重、截断重建和索引持久化。
- `Sources/CodexMeterCore/UsageDirectoryMonitor.swift`：vnode 文件事件监听和防抖回调。
- `Sources/CodexMeter/UsageService.swift`：后台刷新、五分钟对账和主线程快照发布。
- `Sources/CodexMeter/StatusDotIcon.swift`：18 pt 彩色状态圆点绘制。
- `Sources/CodexMeter/SparklineView.swift`：静态折线绘制。
- `Sources/CodexMeter/UsagePopoverController.swift`：方案 D 浮层与鼠标跟踪。
- `Sources/CodexMeter/StatusItemController.swift`：悬停、左键固定、右键菜单。
- `Sources/CodexMeter/LaunchAtLoginController.swift`：系统开机自启注册封装。
- `Sources/CodexMeter/CodexMeterApp.swift`：状态栏应用生命周期和依赖装配。
- `Tests/CodexMeterTests/TestRunner.swift`：无 UI 核心逻辑回归测试。
- `Resources/Info.plist`：`LSUIElement` 和 bundle 元数据。
- `scripts/package-app.sh`：release 构建、组装与签名。

### 任务 1：项目骨架与状态策略

**文件：**
- 创建：`Package.swift`
- 创建：`Sources/CodexMeterCore/UsageModels.swift`
- 创建：`Sources/CodexMeterCore/RateLimitPolicy.swift`
- 创建：`Tests/CodexMeterTests/TestRunner.swift`

- [ ] **步骤 1：创建 SwiftPM 骨架和失败测试**

测试先定义 70/30/10 边界、过期状态和倒计时：

```swift
check(RateLimitPolicy.color(remainingPercent: 70, isStale: false) == .green, "70% green")
check(RateLimitPolicy.color(remainingPercent: 30, isStale: false) == .yellow, "30% yellow")
check(RateLimitPolicy.color(remainingPercent: 10, isStale: false) == .orange, "10% orange")
check(RateLimitPolicy.color(remainingPercent: 9.99, isStale: false) == .red, "below 10% red")
check(RateLimitPolicy.color(remainingPercent: 90, isStale: true) == .unknown, "stale gray")
```

- [ ] **步骤 2：运行测试并确认因类型缺失失败**

运行：`swift run CodexMeterLogicTests`

预期：FAIL，`cannot find 'RateLimitPolicy' in scope`。

- [ ] **步骤 3：实现最小状态策略**

```swift
public enum UsageStatusColor: String, Codable { case green, yellow, orange, red, unknown }

public enum RateLimitPolicy {
  public static func color(remainingPercent: Double?, isStale: Bool) -> UsageStatusColor {
    guard let remainingPercent, !isStale else { return .unknown }
    if remainingPercent >= 70 { return .green }
    if remainingPercent >= 30 { return .yellow }
    if remainingPercent >= 10 { return .orange }
    return .red
  }
}
```

- [ ] **步骤 4：验证状态策略通过**

运行：`swift run CodexMeterLogicTests`

预期：所有当前检查 PASS。

### 任务 2：事件解析与累计值增量

**文件：**
- 创建：`Sources/CodexMeterCore/TokenEventParser.swift`
- 创建：`Sources/CodexMeterCore/SessionUsageAccumulator.swift`
- 修改：`Tests/CodexMeterTests/TestRunner.swift`

- [ ] **步骤 1：编写有效、损坏、重复和重置测试**

```swift
let event = TokenEventParser.parse(line: fixtureLine)
check(event?.totalTokens == 1_250, "parse total tokens")
check(event?.primary?.windowMinutes == 300, "parse five-hour window")
check(TokenEventParser.parse(line: Data("not json".utf8)) == nil, "skip malformed")

var accumulator = SessionUsageAccumulator()
check(accumulator.consume(totalTokens: 100) == 100, "first counter")
check(accumulator.consume(totalTokens: 140) == 40, "counter delta")
check(accumulator.consume(totalTokens: 140) == 0, "duplicate counter")
check(accumulator.consume(totalTokens: 20) == 20, "counter reset")
```

- [ ] **步骤 2：运行并确认解析器缺失失败**

运行：`swift run CodexMeterLogicTests`

预期：FAIL，解析器和累计器未定义。

- [ ] **步骤 3：使用 `JSONSerialization` 实现窄字段解析**

解析必须只接受 `payload.type == "token_count"`，时间戳使用 `ISO8601DateFormatter`，额度窗口允许缺失：

```swift
public struct TokenUsageEvent: Codable, Equatable {
  public let timestamp: Date
  public let totalTokens: Int64?
  public let primary: RateLimitWindow?
  public let secondary: RateLimitWindow?
}
```

- [ ] **步骤 4：实现累计增量并验证**

运行：`swift run CodexMeterLogicTests`

预期：解析、重复和重置检查全部 PASS。

### 任务 3：时间桶、趋势和展示快照

**文件：**
- 创建：`Sources/CodexMeterCore/UsageBuckets.swift`
- 修改：`Sources/CodexMeterCore/UsageModels.swift`
- 修改：`Tests/CodexMeterTests/TestRunner.swift`

- [ ] **步骤 1：编写小时、周一、月桶测试**

使用固定 `Asia/Shanghai` 时区和固定日期：

```swift
var buckets = UsageBuckets(timeZoneIdentifier: "Asia/Shanghai")
buckets.add(tokens: 120, at: isoDate("2026-07-01T01:10:00Z"))
buckets.add(tokens: 80, at: isoDate("2026-07-01T02:10:00Z"))
let snapshot = buckets.snapshot(now: isoDate("2026-07-01T03:00:00Z"))
check(snapshot.todayTotal == 200, "today total")
check(snapshot.hourly.reduce(0, +) == 200, "24 hour series")
check(snapshot.weekly.count == 7, "seven day series")
```

- [ ] **步骤 2：运行并确认分桶 API 缺失失败**

运行：`swift run CodexMeterLogicTests`

预期：FAIL，`UsageBuckets` 未定义。

- [ ] **步骤 3：实现字符串键桶与最近 12 月序列**

```swift
public struct UsageBuckets: Codable, Equatable {
  public var hourly: [String: Int64] = [:]
  public var daily: [String: Int64] = [:]
  public var monthly: [String: Int64] = [:]
  public let timeZoneIdentifier: String
}
```

日历固定 `firstWeekday = 2`；格式键分别为 `yyyy-MM-dd'T'HH`、`yyyy-MM-dd`、`yyyy-MM`。

- [ ] **步骤 4：实现紧凑数值格式化并验证**

覆盖 `999`、`1.2K`、`2.84M`。运行：`swift run CodexMeterLogicTests`，预期全部 PASS。

### 任务 4：可持久化索引与会话汇总

**文件：**
- 创建：`Sources/CodexMeterCore/UsageIndex.swift`
- 修改：`Tests/CodexMeterTests/TestRunner.swift`

- [ ] **步骤 1：编写索引往返、会话撤销和最新额度测试**

```swift
let encoded = try JSONEncoder().encode(index)
let decoded = try JSONDecoder().decode(UsageIndex.self, from: encoded)
check(decoded == index, "index round trip")
check(index.snapshot(now: now).todayTotal == expected, "merge session contributions")
index.removeSession(id: "truncated")
check(index.snapshot(now: now).todayTotal == remaining, "remove truncated contribution")
```

- [ ] **步骤 2：运行并确认索引类型缺失失败**

运行：`swift run CodexMeterLogicTests`

预期：FAIL，`UsageIndex` 未定义。

- [ ] **步骤 3：实现按会话保存的索引**

```swift
public struct SessionUsageIndex: Codable, Equatable {
  public var sessionID: String
  public var path: String
  public var fileIdentity: String
  public var parsedBytes: UInt64
  public var lastTotalTokens: Int64?
  public var buckets: UsageBuckets
  public var latestRateLimit: TokenUsageEvent?
}
```

全局快照通过合并所有会话桶生成，最新额度按事件时间选取。

- [ ] **步骤 4：验证索引测试通过**

运行：`swift run CodexMeterLogicTests`

预期：全部 PASS，编码输出无错误。

### 任务 5：流式扫描与增量日志索引

**文件：**
- 创建：`Sources/CodexMeterCore/JSONLTokenScanner.swift`
- 创建：`Sources/CodexMeterCore/UsageLogIndexer.swift`
- 修改：`Package.swift`
- 修改：`Tests/CodexMeterTests/TestRunner.swift`

- [ ] **步骤 1：将扫描器的纯字节状态机放入 Core 可测试边界并编写测试**

测试输入包括两个完整事件、一个超长非 token 行和一个未完成尾行；断言只返回两个事件，提交偏移停在最后一个换行。

```swift
let result = JSONLTokenScanner.scan(data: fixture, startingOffset: 0)
check(result.events.count == 2, "scan token events only")
check(result.committedOffset == expectedNewlineOffset, "retain incomplete tail")
```

- [ ] **步骤 2：运行并确认扫描器缺失失败**

运行：`swift run CodexMeterLogicTests`

预期：FAIL，`JSONLTokenScanner` 未定义。

- [ ] **步骤 3：实现 64 KB 分块读取和候选行过滤**

扫描器在行首 4 KB 内找不到 `"type":"token_count"` 时跳过该行剩余内容；只对候选行调用 `TokenEventParser`。

- [ ] **步骤 4：实现日志发现、会话 ID 去重和截断重建**

`UsageLogIndexer.refresh()`：

1. 枚举两个日志根目录并按 rollout 会话 ID 分组。
2. 活动目录优先；归档移动沿用会话偏移。
3. 文件长度小于偏移或文件身份变化且不是移动时，撤销会话贡献并重读。
4. 原子写入 `usage-index.json.tmp` 后替换正式索引。

- [ ] **步骤 5：运行核心测试并用临时目录集成验证**

运行：`swift run CodexMeterLogicTests`

预期：扫描、移动去重、截断重建全部 PASS。

### 任务 6：后台服务与低资源目录监听

**文件：**
- 创建：`Sources/CodexMeterCore/UsageDirectoryMonitor.swift`
- 创建：`Sources/CodexMeter/UsageService.swift`

- [x] **步骤 1：实现 vnode DispatchSource 包装器**

监听 `~/.codex/sessions`、`~/.codex/archived_sessions` 及现有 JSONL，延迟 1 秒合并事件；目录变化时重建监听集合，回调只触发后台 `refresh()`。

- [ ] **步骤 2：实现串行后台服务**

```swift
final class UsageService {
  var onSnapshot: ((UsageSnapshot) -> Void)?
  func start()
  func refreshNow()
  func stop()
}
```

索引队列使用 `.utility` QoS；五分钟计时器对账，60 秒计时器只重建倒计时快照。

- [ ] **步骤 3：验证线程边界**

在测试构建中注入临时日志目录和回调队列，断言刷新回调最终在主线程执行，且连续目录事件被防抖成一次刷新。

运行：`swift run CodexMeterLogicTests`，预期全部 PASS。

### 任务 7：状态栏图标、方案 D 浮层和交互

**文件：**
- 创建：`Sources/CodexMeter/StatusDotIcon.swift`
- 创建：`Sources/CodexMeter/SparklineView.swift`
- 创建：`Sources/CodexMeter/UsagePopoverController.swift`
- 创建：`Sources/CodexMeter/StatusItemController.swift`

- [ ] **步骤 1：实现 18 pt 状态点**

使用 `NSImage(size: NSSize(width: 18, height: 18), flipped: false)` 绘制实心点、透明外环和右上高光；`isTemplate = false` 保留状态色。

- [ ] **步骤 2：实现无动画 `SparklineView`**

空数组显示基线；单点居中；多点按最大值归一化并用 `NSBezierPath` 绘制。

- [ ] **步骤 3：实现 320 pt 方案 D 浮层**

使用 AppKit stack views 构建两张额度卡和三张趋势卡；指标区不出现粒度文字，横坐标分别显示 `00 时/现在`、`周一/今天`、动态月份起点/`本月`。

- [ ] **步骤 4：实现悬停、固定和右键菜单**

`NSStatusBarButton` 同时接收左右鼠标事件；`NSTrackingArea` 进入时展示浮层，离开图标和浮层 250 ms 后关闭；左键切换固定；右键创建菜单。

- [ ] **步骤 5：构建 App target**

运行：`swift build`

预期：exit 0，无 Swift 编译错误。

### 任务 8：开机自启与应用生命周期

**文件：**
- 创建：`Sources/CodexMeter/LaunchAtLoginController.swift`
- 创建：`Sources/CodexMeter/CodexMeterApp.swift`
- 创建：`Resources/Info.plist`

- [ ] **步骤 1：实现 `SMAppService.mainApp` 封装**

```swift
enum LaunchAtLoginController {
  static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
  static func setEnabled(_ enabled: Bool) throws {
    if enabled { try SMAppService.mainApp.register() }
    else { try SMAppService.mainApp.unregister() }
  }
}
```

- [ ] **步骤 2：将开关接入右键菜单**

菜单每次打开时读取系统实际状态并设置 `.on/.off`；切换失败弹出 `NSAlert`，随后重新读取状态，默认不主动注册。

- [ ] **步骤 3：实现 accessory 应用生命周期**

设置 `NSApplication.shared.setActivationPolicy(.accessory)`，启动 `UsageService` 与 `StatusItemController`，终止时停止监听和计时器。

- [ ] **步骤 4：验证 Info.plist**

确认 `LSUIElement = true`、`LSMinimumSystemVersion = 13.0`、bundle ID 为 `com.local.CodexMeter`。

### 任务 9：打包与最终验证

**文件：**
- 创建：`scripts/package-app.sh`
- 修改：`docs/superpowers/plans/2026-07-01-codex-meter.md`

- [ ] **步骤 1：运行完整核心测试**

运行：`swift run CodexMeterLogicTests`

预期：所有检查 PASS，退出码 0。

- [ ] **步骤 2：运行 release 构建**

运行：`swift build -c release`

预期：Build complete，退出码 0。

- [ ] **步骤 3：组装并签名 `.app`**

运行：`./scripts/package-app.sh`

预期：生成 `dist/CodexMeter.app`。

- [ ] **步骤 4：验证包结构与签名**

运行：

```bash
plutil -lint dist/CodexMeter.app/Contents/Info.plist
codesign --verify --deep --strict --verbose=2 dist/CodexMeter.app
file dist/CodexMeter.app/Contents/MacOS/CodexMeter
```

预期：plist OK；签名验证成功；可执行文件为当前 Mac 架构的 Mach-O。

- [ ] **步骤 5：启动烟雾验证**

启动应用，确认无 Dock 图标、状态栏显示圆点、悬停和左键出现浮层、右键菜单包含刷新/开机自启/退出。若系统阻止自动 GUI 启动，则明确记录未自动验证的项目，不声称已完成该部分。
