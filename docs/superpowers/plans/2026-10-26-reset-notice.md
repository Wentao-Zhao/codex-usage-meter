# Reset Notice Implementation Plan

**Goal:** Add the approved borderless footer (variant B) without changing existing metric cards or the status icon.

**Architecture:** Independent public announcement service, compact Codable cache and notification ledger. Reuse the existing minute heartbeat for half-hour polling; use asynchronous URLSession requests and native macOS notifications. Never infer personal quota recovery from public announcements.

## Tasks

- [x] Add core tests for decoding, explicit upcoming event selection, expired/inferred/retracted events, freshness, safe source links, deduplication keys and half-hour scheduling.
- [x] Implement `Sources/CodexMeterCore/ResetAnnouncements.swift` with typed feed, event, footer state and scheduling policy.
- [x] Add isolated service tests using URLProtocol and a fake notification sender; cover cache restore, 304, failure, rate limits, duplicate notifications, disabled permission, concurrent requests and cancellation.
- [x] Implement `Sources/CodexMeter/ResetAnnouncementService.swift` and `ResetNotificationSender.swift`. Persist only compact feed and bounded delivered keys in UserDefaults; no personal usage data is sent.
- [x] Add `ResetNoticeFooterView.swift`; retain 320 pt width, all existing metric heights and card order; extend the panel by 42 pt. Footer links to the original post with scope and source in its tooltip.
- [x] Wire the service, shared heartbeat and wake catch-up in `CodexMeterApp.swift` / `UsageService.swift`. Add an opt-in notification toggle and refresh both independent services from the existing refresh action.
- [x] Extend native layout checks for light/dark, weekly-only and long announcement text. Run logic, service and native rendering checks, inspect screenshots, build/sign/restart the local app.
- [x] Document the third-party feed, polling, privacy, notification permissions and limitations. Do not create a DMG or push commits unless requested.

## Verification

`swift run --disable-sandbox CodexMeterLogicTests`

`zsh scripts/check-reset-service.sh`

`zsh scripts/check-quota-layout.sh .build/reset-footer-previews`

`./scripts/package-app.sh`

## Results

- 160 Release logic checks, 26 isolated service checks, 238 native layout checks passed.
- Live public feed decoded with an isolated cache and notifications disabled; latest confirmed reset displayed correctly.
- Light/dark renderings inspected, including ellipsis for long labels and marked offline data.
- Local app rebuilt, signature verified and app restarted. No real notification was sent during automated tests; enabling and macOS banner presentation remain user-controlled.
- Existing test entry moved to `Tests/CodexMeterTests/main.swift` to support multiple Swift test source files.
