# CodexMeter

一个 macOS 13+ 菜单栏小工具，用于轻量展示本机 Codex token 使用情况和剩余额度状态。

## 功能

- 启动后只驻留在菜单栏。
- 状态栏图标使用横向红绿灯样式，根据 5 小时额度剩余比例变色。
- 点击图标展示用量面板，再次点击其他位置自动收起。
- 显示 5 小时剩余比例、距离刷新时间、本周剩余比例和距离周刷新时间。
- 展示今日、本周、本机总量的缩略折线图。
- 右键菜单支持开机自启开关和退出 App。
- 以低频扫描和缓存索引为主，尽量减少 CPU 和磁盘占用。

## 数据来源

CodexMeter 读取本机 Codex 会话日志，聚合 token 使用记录。它不上传数据，也不依赖网络接口。

统计值依赖本机日志的完整性，如果日志被清理或格式变化，显示结果会相应变化。

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

## 运行

```bash
open dist/CodexMeter.app
```

App 打开后不会显示 Dock 图标，也不会弹出主窗口。请看菜单栏右侧状态灯图标。

## 自动化检查

逻辑测试：

```bash
swift run CodexMeterLogicTests
```

发布构建：

```bash
swift build -c release
```

