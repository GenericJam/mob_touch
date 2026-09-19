# AGENTS.md — orientation for AI agents working on mob_touch

You're in **mob_touch**, a Mob capability plugin that streams the user's raw screen touches to a screen. Every finger-down / move / up / cancel on the app's window shows up in the screen's `handle_info/2` as `{:touch, %{phase, x, y, pointer, timestamp}}`, dp coordinates matching the layout. The defining property is **observe without consuming** — buttons and scrolling keep working while you stream.

**Also read [`~/code/mob/AGENTS.md`](../mob/AGENTS.md)** for the system view — the three-repo topology, plugin manifest schema, `MobActivityAware`, how to drive a running app from your session, and the cross-cutting pre-empt-failure rules. This file is mob_touch-specific.

> **Keep this file current.** If you change the message contract, add an option, or hit a gotcha that would trip the next agent, fix it here in the same commit — not a follow-up.

## What mob_touch is, in one paragraph

One public surface — `MobTouch.start/2` and `MobTouch.stop/1`. Start installs a passive whole-window observer on the platform's input layer; the observer emits `{:touch, %{phase: :down | :move | :up | :cancel, x, y, pointer, timestamp}}` to the calling screen's mailbox for every touch on the app surface. `:move` is throttled (`:throttle_ms`, default 16, ≈60Hz); `:down`/`:up`/`:cancel` are never throttled. No runtime permission. The observer stays installed until `stop/1` — leaving it on keeps hitting the mailbox on every touch, so screens that stop needing it should clean up.

## What mob_touch is NOT

* **Not [mob_screencast](https://hexdocs.pm/mob_screencast).** That's the pixel stream (screen contents as encoded H264). mob_touch is the touch stream (x/y coordinates). Different platform surfaces, different consumers.
* **Not a way to override Mob's own gesture system.** Per-widget `on_tap` still fires; mob's synthetic-injection test harness (`Mob.Test.tap_xy`) is unchanged; scrolling still scrolls. The observer forwards every event untouched — do not "improve" it by consuming events, or you break all app input.
* **Not a general input event bus.** It reports touches on the app's window. Not keyboard, not accelerometer, not off-window system swipes (those arrive as `:cancel`).

## The two load-bearing invariants

This is the single most important thing to hold onto while working here.

1. **Observe, never consume.** Android forwards `dispatchTouchEvent` to the original `Window.Callback` unchanged and returns its result; iOS's `UIGestureRecognizer` subclass sets `cancelsTouchesInView = NO` and never advances past `.possible`. A bug here breaks **every** button in the app. Always device-test that a button fires WHILE a screen is streaming. See `decisions/2026-06-17-observe-without-consuming.md`.
2. **The message contract is shared across four surfaces.** `{:touch, %{phase, x, y, pointer, timestamp}}` with phase on the wire as a numeric code (0 down / 1 move / 2 up / 3 cancel), coordinates in dp. The zig thunk (`nativeDeliverTouch`), the Kotlin bridge, the ObjC `send_touch`, and the `MobTouch` moduledoc are one contract. Change one and you must change all four.

## Anatomy of the plugin

* `lib/mob_touch.ex` — the public API. Moduledoc is the canonical contract for the `{:touch, ...}` message shape.
* `lib/mob_touch/demo_screen.ex` — sample `Mob.Screen` reachable at `/mob_touch/demo`; drop it (and the manifest entry) in a real host.
* `src/mob_touch_nif.erl` — Erlang NIF stub, tolerant `on_load`.
* `priv/mob_plugin.exs` — the manifest. `:screens` + `:nifs`; empty `:permissions`; declares `MobActivityAware` on Android (needs the window).
* `priv/native/ios/mob_touch_nif.m` — passive `UIGestureRecognizer` on the key window.
* `priv/native/jni/mob_touch_nif.zig` — Android NIF glue + the `nativeDeliverTouch` thunk.
* `priv/native/android/MobTouchBridge.kt` — the `Window.Callback` observer installed by a reflective `Proxy`, restored on stop.
* `decisions/` — ADRs. Read `2026-06-17-observe-without-consuming.md` first.

## Cross-repo work

**mob (framework):** the bridge implements `MobActivityAware`, so it depends on the host's `MainActivity` calling `MobPluginBootstrap.registerAll(this)`. If you change the activity-lifecycle contract in mob core, this plugin is on the list of things to re-verify. See [`~/code/mob/AGENTS.md`](../mob/AGENTS.md).

**mob_dev:** the plugin ships its native sources; `mob_dev` compiles them from `deps/mob_touch/priv` on `mix mob.deploy --native`. If a change touches the zig NIF or Kotlin bridge, you must run a real native build against a host app before pushing.

## Testing

Elixir suite:

```bash
mix deps.get
mix test
```

Native code isn't exercised by `mix test`. Device test = build a host with `MobTouch.start(socket)` in a screen's `mount/3`, `mix mob.deploy --native`, then:

* Confirm `:down`/`:move`/`:up` arrive in `handle_info/2` as you touch the screen.
* Confirm a normal button on that same screen still fires while touches stream (observe-without-consume).
* Confirm a system swipe delivers a final `:cancel`.

## The pre-empt-failure rules that matter here

1. **Never break observe-without-consume.** If you're editing the Kotlin `Proxy` or the ObjC recognizer, the review question is "does the app's normal input still work?" — not "does the touch stream arrive?" Both must be true, and the failure mode of the first is invisible until a user taps a button.
2. **Never change one side of the contract without the other three.** Wire phase codes, dp coordinates, keyword parity — the zig / kt / objc / moduledoc quartet moves as one.
3. **Screens that call `start/1` must eventually call `stop/1`.** The observer keeps hitting the mailbox for the life of the process otherwise; document it or wire it into `terminate/2` in any demo you ship.
4. **`throttle_ms: 0` is legal but expensive.** Every raw move hits the BEAM. Default 16ms is a real choice, not a placeholder — don't lower it in demos.

## Pre-commit + release

Standard mob plugin gate:

```bash
mix format
mix credo --strict
mix compile --warnings-as-errors
mix test
zig fmt priv/native/jni/*.zig
xcrun clang-format -i priv/native/ios/*.m
mix mob.validate_plugin   # from a host app
```

Activate the pre-push hook once per clone: `git config core.hooksPath .githooks`.

Release = `mix.exs` `@version` bump on master. GH Actions handles tag + GitHub release + Hex publish, signed with the shared mob first-party key. Do NOT bump without explicit permission and a green device build.
