defmodule MobTouch do
  @moduledoc """
  Stream the user's raw screen touches to a screen — a Mob plugin.

  Unlike per-widget `on_tap` (which only fires for a tapped button), this
  observes **every touch on the app's surface** and reports its coordinates, so
  you can build drawing, custom gestures, heatmaps, joysticks, and the like.

  It **observes without consuming**: the touches still reach the app's normal UI,
  so buttons and scrolling keep working while you stream. No runtime permission.

  Updates arrive in the screen's `handle_info/2`:

      handle_info({:touch, %{phase: phase, x: x, y: y, pointer: pointer,
                             timestamp: ms}}, socket)

    * `phase` — `:down` (finger lands), `:move`, `:up` (finger lifts), or
      `:cancel` (the OS took the gesture, e.g. a system swipe).
    * `x`, `y` — **dp** (logical pixels), origin top-left of the app window;
      the same coordinate space the layout uses.
    * `pointer` — a stable id per finger across a gesture, so multi-touch is
      distinguishable. Single-finger use can ignore it.
    * `timestamp` — unix milliseconds.

  iOS: a passive `UIGestureRecognizer` on the key window. Android: a
  `Window.Callback` that observes `dispatchTouchEvent` and forwards it on.

  Call `stop/1` when you no longer need the stream — the observer stays
  installed (and keeps the screen's mailbox busy on every touch) until you do.
  """

  @doc """
  Start streaming touches to the calling screen.

  Options:
    * `:throttle_ms` — the minimum interval between `:move` deliveries (default
      `16`, ≈ 60 Hz). `:down`/`:up`/`:cancel` are never throttled. Raise it to
      cut mailbox traffic for coarse gestures; set `0` for every raw move.
  """
  @spec start(Mob.Socket.t(), keyword()) :: Mob.Socket.t()
  def start(socket, opts \\ []) do
    throttle_ms = Keyword.get(opts, :throttle_ms, 16)
    :mob_touch_nif.touch_start(throttle_ms)
    socket
  end

  @doc "Stop streaming touches and remove the observer."
  @spec stop(Mob.Socket.t()) :: Mob.Socket.t()
  def stop(socket) do
    :mob_touch_nif.touch_stop()
    socket
  end
end
