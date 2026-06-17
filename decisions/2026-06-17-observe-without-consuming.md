# Observe touches without consuming them

- Date: 2026-06-17
- Status: accepted

## Context

mob has per-widget taps (`on_tap`) and a synthetic-injection test harness
(`Mob.Test.tap_xy` etc.), but no way for a screen to read the user's raw touch
coordinates. Features like drawing, custom gestures, and joysticks need the
whole stream of x/y, app-wide — not a per-button callback. The hard requirement
is that reading the stream must not break the app's normal input: buttons and
scrolling have to keep working while a screen observes.

## Decision

Install a **passive observer** at the window level on each platform and forward
every event untouched:

- Android: wrap `Activity.window.callback` with a reflective `Proxy` that
  observes `dispatchTouchEvent`, then delegates to the original callback and
  returns its result. Restored on stop.
- iOS: add a `UIGestureRecognizer` subclass to the key window with
  `cancelsTouchesInView = NO` that reads `touchesBegan/Moved/Ended/Cancelled`
  but never advances past `.possible`, so the app's views still receive the
  touches.

Coordinates are reported in dp (the layout's space, matching `tap_xy`); moves
are throttled (`throttle_ms`, default 16); multi-touch is distinguished by a
`pointer` id. No runtime permission.

## Consequences

- The whole-window scope is all the native layer cheaply offers; a screen sees
  touches anywhere on the app surface (in Sloppy Joe, including the shell — fine,
  since nothing is consumed, the escape hatch still works).
- Observe-without-consume is high-blast-radius: a bug breaks all input, so it
  must be device-verified (tap a button while streaming).
- Synthetic injection stays in mob core's `Mob.Test` harness — a separate
  concern with a different (debug-only) trust posture; not folded in here.
