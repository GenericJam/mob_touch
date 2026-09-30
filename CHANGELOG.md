# Changelog

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
