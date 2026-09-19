# mob_touch — Agent Instructions

**Read [`AGENTS.md`](AGENTS.md) first**, then [`~/code/mob/AGENTS.md`](../mob/AGENTS.md) for the system view. Together they cover the plugin anatomy, the observe-without-consume invariants, the shared `{:touch, ...}` message contract, and the cross-repo work with mob / mob_dev. This file goes deeper on Claude Code-specific workflow detail.

> **Keep AGENTS.md up to date** when you change the message shape, add an option, or hit a gotcha. Out-of-date guidance there causes wrong decisions downstream — fix it in the same commit, not in a follow-up.

## What this repo is

A Mob capability plugin: stream raw screen-touch coordinates to a screen via the platform input layer. `MobTouch.start/2` installs a passive whole-window observer (iOS `UIGestureRecognizer` / Android `Window.Callback` `Proxy`); `MobTouch.stop/1` removes it. The defining property is **observe without consuming** — the app's normal UI must keep working while touches stream.

## Pre-commit checklist

Before committing, run all in this order:

```bash
mix format
mix credo --strict                  # includes ExSlop + jump_credo_checks
mix compile --warnings-as-errors
mix test
zig fmt priv/native/jni/*.zig
xcrun clang-format -i priv/native/ios/*.m
mix mob.validate_plugin             # from a host app
```

Pre-push hook (`.githooks/pre-push`) adds format + credo strict + compile + fast tests on every push. Activate once per clone:

```bash
git config core.hooksPath .githooks
```

Native code isn't exercised by `mix test`. Verify on a device (`mix mob.deploy --native` a host that calls `MobTouch.start(socket)` in a screen `mount/3`, confirm `:down`/`:move`/`:up` arrive AND a button on the same screen still fires).

### Tests are part of the change

New behaviour ships with a test unless the change is small enough that a test would only restate it. The bar is: **would this test fail if the fix were reverted?** For mob_touch specifically, any change to option normalisation or the `{:touch, %{...}}` shape needs a test that pins the contract.

### Decision log — check both directions

Non-obvious calls go in `decisions/YYYY-MM-DD-slug.md`. Append; never edit a landed one.

Before committing:
* **Does this need a new record?** Any tradeoff or workaround — grep `decisions/` first to make sure you aren't restating one.
* **Does this INVALIDATE an existing record?** A record asserting a property the code no longer has is worse than no record. Correct in place with a note about what was wrong, don't quietly delete. `2026-06-17-observe-without-consuming.md` is the load-bearing one.

### Adversarial review — before every non-trivial commit

Spawn a subagent, point it at the diff, tell it to find defects. Especially:

* **Observe-without-consume regressions.** The Kotlin `Proxy` returning the wrong value, or the ObjC recognizer advancing state — silent breakage of every button in the app.
* **Message-contract drift.** The zig / kt / objc / moduledoc quartet moves as one; a subagent reviewing only one side won't catch a mismatch.

Skip only for: formatting, a typo, a version bump, a changelog edit.

## Release flow

Canonical process in [`~/code/mob/RELEASE.md`](../mob/RELEASE.md). mob_touch specifics:

* `@version` in `mix.exs` is the trigger. Push it to master, GH Actions handles tag / GitHub release / Hex publish, signed with the shared mob first-party key.
* **Never ship without a device build.** Simulators don't exercise the platform's real input layer — `mix mob.deploy --native` to a real phone, drive a screen that streams touches, verify observe-without-consume.
