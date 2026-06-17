# Changelog

## 0.1.0

Initial release. Stream the user's raw screen touches to a screen:

- `MobTouch.start/2` / `MobTouch.stop/1`.
- Delivers `{:touch, %{phase: :down | :move | :up | :cancel, x:, y:, pointer:,
  timestamp:}}`; coordinates in dp, multi-touch via `pointer`, `:throttle_ms`
  option for `:move` coalescing.

Observes **without consuming** — the app's normal UI keeps working while you
stream. Android via a `Window.Callback` `dispatchTouchEvent` observer; iOS via a
passive `UIGestureRecognizer` on the key window. No runtime permission.
