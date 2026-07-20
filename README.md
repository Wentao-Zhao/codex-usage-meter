# CodexMeter

一个 macOS 13+ 菜单栏小工具，用于轻量展示本机 Codex token 使用情况和当前可用的额度状态。

## 功能

- 启动后只驻留在菜单栏。
- 状态栏图标使用横向红绿灯样式：有 5 小时额度时按其剩余比例变色，没有时自动改用周额度。
- 点击图标展示用量面板，点击其他位置自动收起。
- Codex 提供 5 小时额度时，显示剩余比例和距离刷新还有多少分钟。
- 显示本周剩余比例、距离周刷新还有多少天。
- Codex 未提供 5 小时额度时，自动隐藏对应卡片，并将周额度卡片铺满面板宽度。
- 展示今日、本周、本机总量的缩略折线图。
- 本机总量区分普通输入、缓存输入和输出 Token，并按当前模型费率显示等效 credits。
- 右键菜单支持开机自启开关和退出 App。
- 以低频扫描和缓存索引为主，尽量减少 CPU 和磁盘占用。

## 状态灯含义

状态灯优先根据 5 小时剩余额度变化；该额度不可用时，自动根据周剩余额度变化：

- 绿色：剩余 >= 70%。
- 黄色：剩余 >= 30% 且 < 70%。
- 橙色：剩余 > 10% 且 < 30%。
- 红色：剩余 <= 10%。

## 数据来源

CodexMeter 读取本机 Codex 会话日志，聚合 token 使用记录。它会识别分叉子任务携带的父任务历史，避免同一段累计用量被重复统计。它不上传数据，也不依赖网络接口。

原始总量表示模型处理过的 Token 数，包含缓存输入；等效 credits 会分别按普通输入、缓存输入和输出的内置费率折算。费率或日志格式变化时，最终结果仍以 Codex 官方用量页面为准。

统计值依赖本机日志的完整性。如果日志被清理或日志目录变化，显示结果会相应变化。

## 安装

从 GitHub Releases 下载最新 DMG：

```text
CodexMeter-1.1.0.dmg
```

安装步骤：

1. 打开 DMG。
2. 将 `CodexMeter.app` 拖到 `Applications`。
3. 如果 macOS 阻止直接打开，请右键 `CodexMeter.app`，选择「打开」，并在系统提示中确认。
4. App 启动后不会显示 Dock 图标，只驻留在菜单栏。

## 使用

1. 打开 `CodexMeter.app`。
2. 查看菜单栏右侧状态灯。
3. 左键点击状态灯查看详细用量面板。
4. 右键点击状态灯打开菜单，可配置开机自启或退出 App。

## 隐私边界

- 只读取本机 Codex 日志。
- 不上传日志，不上传 token 用量。
- 不需要 GitHub、OpenAI 或 Codex API 凭证。
- 只做本机估算展示，最终额度以 Codex 官方界面为准。

## 构建

```bash
cd CodexMeter
./scripts/package-app.sh
```

生成文件：

```text
dist/CodexMeter.app
```

如果本机 Command Line Tools 存在 Swift SDK 小版本不匹配问题，可以指定已安装 SDK：

```bash
CODEX_METER_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
  ./scripts/package-app.sh
```

## 生成 DMG

```bash
./scripts/package-dmg.sh
```

生成文件：

```text
dist/CodexMeter-1.1.0.dmg
```

## 自动化检查

逻辑测试：

```bash
swift run CodexMeterLogicTests
```

发布构建：

```bash
swift build -c release
```
