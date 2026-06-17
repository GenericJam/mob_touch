# mob_touch — Agent Instructions

A Mob capability plugin: stream raw screen-touch coordinates to a screen, via
the platform input layer. The defining constraint is **observe without
consuming** — the app's normal UI must keep working while touches stream.

## Layout

- `lib/mob_touch.ex` — the public `start/2` / `stop/1` API.
- `lib/mob_touch/demo_screen.ex` — a sample `Mob.Screen` (manifest `:screens`).
- `src/mob_touch_nif.erl` — the Erlang NIF stub (tolerant `on_load`).
- `priv/mob_plugin.exs` — the manifest (the bridge implements `MobActivityAware`).
- `priv/native/jni/mob_touch_nif.zig` — Android NIF glue + the `nativeDeliverTouch`
  thunk.
- `priv/native/android/MobTouchBridge.kt` — the `Window.Callback` observer.
- `priv/native/ios/mob_touch_nif.m` — the passive `UIGestureRecognizer`.

## The two load-bearing invariants

1. **Observe, never consume.** Android forwards `dispatchTouchEvent` to the
   original callback unchanged and returns its result; iOS sets
   `cancelsTouchesInView = NO` and never advances the recognizer past
   `.possible`. A mistake here breaks *all* app input — always device-test that a
   button still fires WHILE streaming.
2. **The message contract is shared.** `{:touch, %{phase, x, y, pointer,
   timestamp}}`, phase as a numeric code on the wire (0 down / 1 move / 2 up /
   3 cancel), coordinates in dp. The zig thunk, the Kotlin `nativeDeliverTouch`,
   the ObjC `send_touch`, and the `MobTouch` moduledoc are one contract.

The bridge implements `MobActivityAware` (it needs the window), so it depends on
the host's `MainActivity` calling `MobPluginBootstrap.registerAll(this)`.

## Pre-commit checklist

```bash
mix format
mix credo --strict
mix compile --warnings-as-errors
mix test
zig fmt priv/native/jni/*.zig
xcrun clang-format -i priv/native/ios/*.m
mix mob.validate_plugin   # from a host app
```

Native code isn't exercised by `mix test`; verify on a device (`mix mob.deploy
--native`, drive a screen that calls `MobTouch`, confirm observe-without-consume).

## Release

`mix.exs` version is the source of truth. Bump it, update `CHANGELOG.md`, sign
with the shared mob key (`cp ~/.mob/keys/<sibling>.priv ~/.mob/keys/mob_touch.priv
&& mix mob.plugin.sign`), then publish (GitHub release workflow on push, or
`HEX_API_KEY=… mix hex.publish` with `~/.hex/hex.config` moved aside). A published
version is permanent — get a native build green on hardware first.

## Decision log

Non-obvious calls go in `decisions/YYYY-MM-DD-slug.md`. Append; never edit a
landed one.
