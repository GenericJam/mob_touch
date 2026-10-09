# Changelog

## Unreleased

### Added
- **On-device self-test** (MOB-418). `MobTouch.SelfTest` implements
  `Mob.Plugin.SelfTest` and is declared in the manifest as `selftest:`.
  `touch_start/1` must answer `:ok`; on Android the test then injects a
  touch at (8, 8) dp with mob's in-process `press_down_xy` / `press_up_xy`
  and passes only when the observer delivers the `:down` and `:up` at those
  dp coordinates (NIF linked, bridge registered with the Activity, the
  `Window.Callback` proxy installed, delivery wired). iOS has no in-process
  injection that reaches UIKit, so there the proof is `touch_start/1` and
  `touch_stop/0` both answering `:ok` from the Objective-C NIF. Run it with
  `mix mob.selftest` from a host app (mob_dev 0.7.17). Requires mob 0.9.15;
  `mob_version` in the manifest is now `~> 0.9`.
- **Android: the NIF reports an unregistered bridge.** `touch_start/1` and
  `touch_stop/0` answer `{:error, :bridge_not_registered}` when
  `MobTouchBridge.register()` never ran or a method-ID lookup failed,
  instead of calling JNI through a null class (which aborts the VM).
  `MobTouch.start/2` and `stop/1` are unchanged (they ignore the return
  value); the self-test turns it into a failure.

## 0.1.1 - 2026-09-30

### Changed
- **Re-signed with plugin envelope v2** (MOB-287). mob_dev 0.7.2+ verifies
  this signature before evaluating the manifest. mob_dev 0.7.0 / 0.7.1 can't
  read v2 signatures and report this release as `invalid signature` —
  upgrade the host app to `{:mob_dev, "~> 0.7.2", only: :dev, runtime: false}`.
  No plugin code changes.

## 0.1.0

Initial release. Stream the user's raw screen touches to a screen:

- `MobTouch.start/2` / `MobTouch.stop/1`.
- Delivers `{:touch, %{phase: :down | :move | :up | :cancel, x:, y:, pointer:,
  timestamp:}}`; coordinates in dp, multi-touch via `pointer`, `:throttle_ms`
  option for `:move` coalescing.

Observes **without consuming** — the app's normal UI keeps working while you
stream. Android via a `Window.Callback` `dispatchTouchEvent` observer; iOS via a
passive `UIGestureRecognizer` on the key window. No runtime permission.
