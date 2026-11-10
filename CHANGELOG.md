# Changelog

All notable changes to this project are documented in this file.

## [1.0.0] - 2026-11-10

### Added

- First public release.
- Board-specific compatibility gate for Xiaomi `jaws` / AMLS905X4.
- Conservative local-gateway failure detector with boot and network grace periods.
- Android 14 Wi-Fi subsystem recovery through `cmd wifi trigger-recovery`.
- User-intent gate that never enables intentionally disabled Wi-Fi.
- Thirty-minute cooldown, two-per-six-hour burst limit, and six-hour failure lockout.
- Bounded private diagnostics: three 256 KiB snapshots and a rotated 64 KiB service log.
- Observe-only mode, singleton process lock, safe uninstall, and monotonic timing.
- Reproducible ZIP builder, verifier, policy tests, bilingual documentation, and CI.
