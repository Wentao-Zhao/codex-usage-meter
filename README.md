# CodexMeter

一个 macOS 13+ 菜单栏小工具，用于轻量展示本机 Codex token 使用情况和当前可用的额度状态。

## 功能

- 启动后只驻留在菜单栏。
- 状态栏图标使用横向红绿灯样式：有 5 小时额度时按其剩余比例变色，没有时自动改用周额度。
- 点击图标展示用量面板，点击其他位置自动收起。
- Codex 提供 5 小时额度时，显示剩余比例和距离刷新还有多少分钟。
- 显示本周剩余比例、距离周刷新还有多少天。
- Codex 未提供 5 小时额度时，自动隐藏对应卡片，并将周额度卡片铺满面板宽度。
- 今日消耗展示小时趋势，本周消耗展示逐日对比柱图。
- 本机总量使用独立数字和右侧比例条，下方以三列展示普通输入、缓存输入、输出的数值与占比，并显示等效 credits。
- 百分比位于各分栏右上方，小于 1% 的非零占比显示为 `<1%`；悬停总量或分项数值可查看完整 Token 数。
- 右键菜单支持开机自启开关和退出 App。
- 面板底部的无框页脚展示额外额度重置／重置卡发放动态，点击查看来源，悬停查看适用范围。
- 右键「重置动态通知」可开启 macOS 系统通知，默认关闭；不增加状态栏标记。
- 以低频扫描和缓存索引为主，尽量减少 CPU 和磁盘占用。

## 状态灯含义

状态灯优先根据 5 小时剩余额度变化；该额度不可用时，自动根据周剩余额度变化：

- 绿色：剩余 >= 70%。
- 黄色：剩余 >= 30% 且 < 70%。
- 橙色：剩余 > 10% 且 < 30%。
- 红色：剩余 <= 10%。

## 数据来源

CodexMeter 读取本机 Codex 会话日志，聚合 token 使用记录。它会识别分叉子任务携带的父任务历史，避免同一段累计用量被重复统计。

额度数据通过本机 Codex 提供的 `account/rateLimits/read` 接口读取，并优先选择 Codex 主额度，避免被其他额度分组覆盖。额度每 5 分钟低频刷新；暂时读取失败时保留上次成功结果，并回退到会话日志中的额度信息。CodexMeter 不上传日志，也不需要额外的 API 凭证。

自动识别新版桌面端的 `codex-cli/bin/codex` 入口、嵌套的 CodexCLI App 和旧版内置程序路径，优先使用已安装桌面端提供的服务。

原始总量表示模型处理过的 Token 数，包含缓存输入；等效 credits 会分别按普通输入、缓存输入和输出的内置费率折算。费率或日志格式变化时，最终结果仍以 Codex 官方用量页面为准。

统计值依赖本机日志的完整性。如果日志被清理或日志目录变化，显示结果会相应变化。

## 安装

从 GitHub Releases 下载最新 DMG：

```text
CodexMeter-1.3.0.dmg
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
4. 右键点击状态灯打开菜单，可配置开机自启、重置动态通知、立即刷新或退出 App。

## 重置动态

重置动态来自 [AIHOT 的公开重置监控](https://aihot.news/codex-reset)，不是个人五小时／周额度的自然刷新提醒，也不是 OpenAI 官方账户接口。它不能保证某次重置适用于你的账户，发放重置卡也不代表额度已自动恢复。

- 通过 `GET https://aihot.news/api/v1/codex-resets` 每半小时异步检查；启动或唤醒后补查错过的时段。右键「立即刷新」同时更新个人用量和公开动态。
- 只对明确、未到期且来源核验时间未过期的预告发通知，不根据历史间隔或推测时间预测重置。
- 显示北京时间，并保留原文「前」「左右」等限定词；无有效预告时显示最近一次有日期可核实的确认记录。
- 同一事件不重复通知；时间、类型或适用范围变化时可再次通知。去重记录跨重启保存。
- 失败时保留缓存并标注「数据待更新」，不使用旧数据发送通知；服务限流时尊重等待时间。
- 通知默认关闭。右键开启时才申请系统通知权限；若没有弹窗，请检查系统设置 → 通知 → CodexMeter，以及专注模式／共享屏幕限制。
- 电脑休眠、App 退出或网络不可用期间不能保证及时提醒。最终可用额度以个人 Codex 界面为准。

## 隐私边界

- 个人用量只读取本机 Codex 日志和本机 Codex 返回的账户额度。
- 不上传日志，不上传 token 用量。
- 不需要 GitHub、OpenAI 或 Codex API 凭证。
- 只做本机估算展示，最终额度以 Codex 官方界面为准。
- 公开重置动态需要访问 AIHOT；对方会收到正常的网络请求，但不会收到本机日志、对话、Token 用量或 Codex 登录凭据。不请求头像或追踪资源。
- 仅在本地保存精简的动态缓存、通知开关及最近 200 条已发送标识。

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
dist/CodexMeter-1.3.0.dmg
```

## 自动化检查

逻辑测试：

```bash
swift run CodexMeterLogicTests
```

程序路径回归检查（无需联网）：

```bash
zsh scripts/check-account-connection.sh --offline
```

实际账户额度连接检查（使用本机 Codex 登录状态）：

```bash
zsh scripts/check-account-connection.sh
```

原生额度卡片布局检查（浅色/深色、不同百分比、仅周额度；可选输出预览图）：

```bash
zsh scripts/check-quota-layout.sh .build/quota-layout-previews
```

重置动态服务检查（隔离缓存、模拟 HTTP 和通知，不联网或发送真实通知）：

```bash
zsh scripts/check-reset-service.sh
```

发布构建：

```bash
swift build -c release
```
