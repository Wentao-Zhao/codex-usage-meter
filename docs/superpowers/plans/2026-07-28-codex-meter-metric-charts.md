# CodexMeter 消耗指标图改版实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将今日、本周和本机总量替换为同期对比折线、分组柱状图和 Token 构成环，并统一四个模块标题样式。

**架构：** `CodexMeterCore` 负责生成同期时间序列、对比状态和归一化图表几何；AppKit 层只绑定不可变快照并静态绘制。保留现有低频扫描与增量索引，不为图表增加定时器、网络请求或磁盘读取。

**技术栈：** Swift 5.9、AppKit、Foundation、NSBezierPath、现有可执行测试目标 `CodexMeterLogicTests`

---

## 文件结构

- 创建 `Sources/CodexMeterCore/UsageComparison.swift`：定义同期对比状态和百分比规则。
- 创建 `Sources/CodexMeterCore/UsageChartGeometry.swift`：生成共享尺度折线点、分组柱比例和 Token 构成比例。
- 修改 `Sources/CodexMeterCore/UsageBuckets.swift`：从历史小时、日桶生成今日/昨日同期和本周/上周同期序列。
- 修改 `Sources/CodexMeterCore/UsageIndex.swift`：把新增序列和同期总量暴露给 `UsageSnapshot`。
- 创建 `Sources/CodexMeter/ComparisonLineChartView.swift`：静态绘制今日实线、面积和昨日虚线。
- 创建 `Sources/CodexMeter/GroupedBarChartView.swift`：静态绘制本周与上周同期分组柱。
- 创建 `Sources/CodexMeter/TokenCompositionRingView.swift`：静态绘制 Token 构成环。
- 修改 `Sources/CodexMeter/UsagePopoverController.swift`：调整浮层、标题、卡片布局和绑定。
- 修改 `Tests/CodexMeterTests/TestRunner.swift`：覆盖时间切片、对比边界、图表几何和构成比例。

### 任务 1：同期对比状态

**文件：**
- 创建：`Sources/CodexMeterCore/UsageComparison.swift`
- 测试：`Tests/CodexMeterTests/TestRunner.swift`

- [ ] **步骤 1：编写失败的对比状态测试**

```swift
check(
  UsageComparison.resolve(current: 118, previous: 100) == .increased(percent: 18),
  "comparison reports increase"
)
check(
  UsageComparison.resolve(current: 91, previous: 100) == .decreased(percent: 9),
  "comparison reports decrease"
)
check(
  UsageComparison.resolve(current: 100, previous: 100) == .unchanged,
  "comparison reports unchanged"
)
check(
  UsageComparison.resolve(current: 10, previous: 0) == .added,
  "comparison reports newly added usage"
)
check(
  UsageComparison.resolve(current: 0, previous: 0) == .empty,
  "comparison reports empty periods"
)
```

- [ ] **步骤 2：运行测试并确认因接口不存在而失败**

运行：

```bash
HOME="$PWD/.swift-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
swift run CodexMeterLogicTests
```

预期：编译失败，提示找不到 `UsageComparison`。

- [ ] **步骤 3：实现最小对比模型**

```swift
public enum UsageComparisonState: Equatable, Sendable {
  case empty
  case added
  case unchanged
  case increased(percent: Int)
  case decreased(percent: Int)
}

public enum UsageComparison {
  public static func resolve(current: Int64, previous: Int64) -> UsageComparisonState {
    let current = max(0, current)
    let previous = max(0, previous)
    guard previous > 0 else {
      return current > 0 ? .added : .empty
    }
    guard current != previous else {
      return .unchanged
    }
    let percent = max(1, Int((abs(Double(current - previous)) / Double(previous) * 100).rounded()))
    return current > previous ? .increased(percent: percent) : .decreased(percent: percent)
  }
}
```

- [ ] **步骤 4：运行测试确认通过**

运行相同的 `swift run CodexMeterLogicTests`，预期全部现有检查和新增 5 项检查通过。

- [ ] **步骤 5：提交**

```bash
git add Sources/CodexMeterCore/UsageComparison.swift Tests/CodexMeterTests/TestRunner.swift
git commit -m "feat: add usage period comparison"
```

### 任务 2：生成同期时间序列

**文件：**
- 修改：`Sources/CodexMeterCore/UsageBuckets.swift`
- 修改：`Sources/CodexMeterCore/UsageIndex.swift`
- 测试：`Tests/CodexMeterTests/TestRunner.swift`

- [ ] **步骤 1：编写失败的昨日与上周同期测试**

建立 `Asia/Shanghai` 桶，在星期三 `10:30` 生成快照：

```swift
let comparisonNow = isoDate("2026-07-29T02:30:00.000Z")
var comparisonBuckets = UsageBuckets(timeZoneIdentifier: "Asia/Shanghai")
comparisonBuckets.add(tokens: 30, at: isoDate("2026-07-29T01:10:00.000Z"))
comparisonBuckets.add(tokens: 20, at: isoDate("2026-07-28T01:10:00.000Z"))
comparisonBuckets.add(tokens: 40, at: isoDate("2026-07-22T01:10:00.000Z"))
let comparisonSnapshot = comparisonBuckets.snapshot(now: comparisonNow)

check(comparisonSnapshot.hourly.count == 11, "today series stops at current hour")
check(comparisonSnapshot.previousDayHourly.count == 11, "yesterday series matches current range")
check(comparisonSnapshot.previousDayTotal == 20, "previous day total uses same hour range")
check(comparisonSnapshot.weekly.count == 3, "week series stops at current weekday")
check(comparisonSnapshot.previousWeekDaily.count == 3, "previous week series matches current range")
check(comparisonSnapshot.previousWeekTotal == 40, "previous week total uses same weekday range")
```

- [ ] **步骤 2：运行测试并确认新增属性或数量断言失败**

运行 `swift run CodexMeterLogicTests`，预期失败原因是新增快照属性不存在或现有序列仍为 24/7 项。

- [ ] **步骤 3：扩展 `UsageBucketSnapshot`**

新增：

```swift
public let previousDayTotal: Int64
public let previousWeekTotal: Int64
public let previousDayHourly: [Int64]
public let previousWeekDaily: [Int64]
```

在 `snapshot(now:)` 中：

- 当前小时范围为 `0...currentHour`。
- 当前星期范围为周一到今天的偏移。
- 昨日使用相同小时偏移读取 `hourly`。
- 上周使用相同星期偏移读取 `daily`。
- `hourly` 和 `weekly` 改为只返回当前有效范围。

- [ ] **步骤 4：扩展 `UsageSnapshot` 与 `UsageIndex.snapshot`**

新增同名属性并从 `UsageBucketSnapshot` 直接传递：

```swift
public let previousDayTotal: Int64
public let previousWeekTotal: Int64
public let previousDayHourly: [Int64]
public let previousWeekDaily: [Int64]
```

- [ ] **步骤 5：运行测试确认通过**

运行 `swift run CodexMeterLogicTests`，预期新增时间切片检查通过，现有 24/7 数量检查同步改为当前时间范围断言。

- [ ] **步骤 6：提交**

```bash
git add Sources/CodexMeterCore/UsageBuckets.swift Sources/CodexMeterCore/UsageIndex.swift Tests/CodexMeterTests/TestRunner.swift
git commit -m "feat: expose previous usage periods"
```

### 任务 3：静态图表几何

**文件：**
- 创建：`Sources/CodexMeterCore/UsageChartGeometry.swift`
- 测试：`Tests/CodexMeterTests/TestRunner.swift`

- [ ] **步骤 1：编写失败的共享尺度和构成测试**

```swift
let comparisonGeometry = UsageChartGeometry.lines(
  current: [0, 20, 40],
  previous: [0, 50, 100]
)
check(comparisonGeometry.current.last?.y == 0.4, "line series share one maximum")
check(comparisonGeometry.previous.last?.y == 1, "previous line reaches shared maximum")

let groupedBars = UsageChartGeometry.bars(current: [40, 100], previous: [80, 50])
check(groupedBars[0].current == 0.4 && groupedBars[0].previous == 0.8, "bars share one maximum")
check(groupedBars[1].current == 1 && groupedBars[1].previous == 0.5, "bar pairs preserve ratio")

let composition = UsageChartGeometry.composition(
  usage: TokenUsage(inputTokens: 95, cachedInputTokens: 71, outputTokens: 5, totalTokens: 100)
)
check(composition.uncachedInput == 0.24, "composition uncached input")
check(composition.cachedInput == 0.71, "composition cached input")
check(composition.output == 0.05, "composition output")
```

- [ ] **步骤 2：运行测试并确认因 `UsageChartGeometry` 不存在而失败**

运行 `swift run CodexMeterLogicTests`，预期编译失败。

- [ ] **步骤 3：实现几何值类型**

```swift
public struct ComparisonLineGeometry: Equatable, Sendable {
  public let current: [SparklinePoint]
  public let previous: [SparklinePoint]
}

public struct GroupedBarFraction: Equatable, Sendable {
  public let current: Double
  public let previous: Double
}

public struct TokenComposition: Equatable, Sendable {
  public let uncachedInput: Double
  public let cachedInput: Double
  public let output: Double
}
```

`UsageChartGeometry` 使用两个序列的共同最大值归一化；总量为零时返回零值。构成中的未分类 Token 合并到普通输入。

- [ ] **步骤 4：运行测试确认通过**

运行 `swift run CodexMeterLogicTests`，预期所有几何检查通过且结果位于 `0...1`。

- [ ] **步骤 5：提交**

```bash
git add Sources/CodexMeterCore/UsageChartGeometry.swift Tests/CodexMeterTests/TestRunner.swift
git commit -m "feat: add usage chart geometry"
```

### 任务 4：AppKit 图表与浮层布局

**文件：**
- 创建：`Sources/CodexMeter/ComparisonLineChartView.swift`
- 创建：`Sources/CodexMeter/GroupedBarChartView.swift`
- 创建：`Sources/CodexMeter/TokenCompositionRingView.swift`
- 修改：`Sources/CodexMeter/UsagePopoverController.swift`

- [ ] **步骤 1：实现今日对比折线**

`ComparisonLineChartView` 接收 `currentValues`、`previousValues` 和 `lineColor`：

- 使用 `UsageChartGeometry.lines` 获取共享尺度点。
- 先绘制当前序列低透明面积。
- 使用 `setLineDash([3, 4], count: 2, phase: 0)` 绘制昨日虚线。
- 使用 `2 pt` 圆角实线绘制今日序列。
- 在今日末端绘制半径 `2.5 pt` 圆点。

- [ ] **步骤 2：实现本周分组柱**

`GroupedBarChartView` 接收 `currentValues` 和 `previousValues`：

- 使用 `UsageChartGeometry.bars` 获取比例。
- 每组灰色柱在左，蓝色柱在右。
- 柱宽由可用宽度和组数计算，最小间隔 `4 pt`。
- 所有柱限定在视图绘制矩形内，底部不绘制横轴文字。

- [ ] **步骤 3：实现 Token 构成环**

`TokenCompositionRingView` 接收 `TokenUsage`：

- 使用 `UsageChartGeometry.composition` 获取三个比例。
- 使用 `NSBezierPath.appendArc` 绘制三段固定颜色圆弧。
- 总量为零时只绘制中性灰圆环。
- 圆心由外部 `NSTextField` 叠放总量和“全部 Token”，避免在 `draw` 中绘制文字。

- [ ] **步骤 4：重构卡片绑定和标题**

在 `UsagePopoverController.swift` 中：

- 将四个标题替换为统一 `SectionLabelView`，字号 `9 pt`，前置 `3 x 9 pt` 色条。
- 今日卡绑定 `snapshot.hourly`、`snapshot.previousDayHourly` 和 `UsageComparison.resolve`。
- 本周卡绑定 `snapshot.weekly`、`snapshot.previousWeekDaily` 和 `UsageComparison.resolve`。
- 本机总量卡绑定 `allTimeUsage`，右侧三行显示绝对值和整数占比。
- 移除 `SparklineView` 在三张指标卡中的使用。
- 浮层宽度保持 `320 pt`，高度设为 `444 pt`。
- 今日、本周卡高度设为约 `82 pt`，本机总量卡高度设为约 `104 pt`。
- 本周柱图底部与横轴保持至少 `8 pt` 间距。

- [ ] **步骤 5：构建并修复编译问题**

运行：

```bash
HOME="$PWD/.swift-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
swift build -c release
```

预期：release 构建成功，无 Swift 编译错误。

- [ ] **步骤 6：提交**

```bash
git add Sources/CodexMeter Sources/CodexMeterCore
git commit -m "feat: redesign usage metric charts"
```

### 任务 5：完整验证与本地视觉检查

**文件：**
- 可能修改：`Sources/CodexMeter/UsagePopoverController.swift`
- 可能修改：三个新图表视图

- [ ] **步骤 1：运行完整核心测试**

```bash
HOME="$PWD/.swift-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
swift run CodexMeterLogicTests
```

预期：输出 `PASS: N checks`，退出码为 0。

- [ ] **步骤 2：打包本地 App**

```bash
CODEX_METER_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
HOME="$PWD/.swift-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
./scripts/package-app.sh
```

预期：生成 `dist/CodexMeter.app`，`codesign --verify --deep --strict` 通过。

- [ ] **步骤 3：启动本地 App 并截图检查**

- 退出旧的 CodexMeter 进程。
- 打开 `dist/CodexMeter.app`。
- 点击状态栏图标展示浮层并截图。
- 检查标题层级、柱图横轴间距、圆环与右侧三行是否溢出。

- [ ] **步骤 4：对视觉问题做最小调整并重复测试、构建**

只调整间距、字号和绘制矩形，不改变确认的数据口径。每次调整后重新运行核心测试和 release 构建。

- [ ] **步骤 5：最终提交**

```bash
git add Sources Tests docs/superpowers/plans/2026-07-28-codex-meter-metric-charts.md
git commit -m "test: verify redesigned usage metrics"
```
