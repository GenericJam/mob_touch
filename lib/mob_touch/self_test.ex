defmodule MobTouch.SelfTest do
  @moduledoc """
  The plugin's on-device proof (`Mob.Plugin.SelfTest`), run by
  `mix mob.selftest` and mob_ci for every activated plugin.

  `touch_start/1` installs the observer for the calling process, the test
  checks what comes back, and `touch_stop/0` removes the observer again.

    * **Android**: after `touch_start/1` answers `:ok`, the test puts a
      synthetic finger down at (8, 8) dp with mob's in-process
      `:mob_nif.press_down_xy/3`, which dispatches real `MotionEvent`s at the
      window's decor view (the path a finger takes through
      `Window.Callback`). The finger is never lifted: mob's bridge cancels it
      after 100 ms, or at once when no view consumed the down (`{:error,
      :dispatch_failed}`, the corner of a blank screen), so nothing on the
      host's screen is ever clicked. The test passes when the observer
      delivers `{:touch, %{phase: :down}}` and then `:cancel` (or `:up`) at
      those dp coordinates: the zig NIF is linked, the Kotlin
      `MobTouchBridge` registered and has the Activity, its observer sits in
      the window's callback chain and the `nativeDeliverTouch` thunk
      reaches the BEAM in dp. The observer is installed asynchronously on
      the UI thread, so an injection that overtook the install is retried
      once before the test fails. `{:error, :bridge_not_registered}` from the
      NIF, or no touch for either injection, fails. When the host cannot
      inject (`:not_loaded` from a generated `MobBridge.kt` older than the
      held-press methods, `:no_window`, `:timeout`, a finger already held)
      the test cannot observe anything and skips, saying why.
    * **iOS**: mob has no in-process touch injection that reaches UIKit
      (`press_down_xy/3` answers `{:error, :not_supported}`), so the proof
      is the native round trip: `touch_start/1` and `touch_stop/0` must both
      answer `:ok` from the Objective-C NIF, which queues the
      `UIGestureRecognizer` install and removal on the main queue.

  The host stub's `nif_not_loaded` is a failure. The observer follows the
  last caller of `touch_start/1`, so a screen that was streaming touches
  when the test ran stops receiving them until it calls `MobTouch.start/2`
  again.
  """
  @behaviour Mob.Plugin.SelfTest

  @x 8.0
  @y 8.0
  @max_hold 100
  @answer_timeout 1_500

  @impl true
  def run(%{platform: platform}) do
    case :mob_touch_nif.touch_start(0) do
      :ok ->
        result = prove(platform)
        stop_result = :mob_touch_nif.touch_stop()
        combine(result, stop_result)

      other ->
        classify_nif("touch_start/1", other)
    end
  rescue
    e in ErlangError ->
      {:fail, "mob_touch_nif is not linked into this build: #{Exception.message(e)}"}
  end

  defp prove(:ios), do: :pass
  defp prove(:android), do: prove_android(&press/0, @answer_timeout)

  defp press do
    :mob_nif.press_down_xy(@x, @y, @max_hold)
  rescue
    e -> {:error, {:raised, Exception.message(e)}}
  end

  @doc false
  # The Android proof with the injection passed in, so the unit tests can
  # play the bridge: two attempts, each must be accepted and observed.
  @spec prove_android((-> term()), non_neg_integer()) :: Mob.Plugin.SelfTest.result()
  def prove_android(press, timeout) do
    with {:fail, _} <- attempt(press, timeout) do
      attempt(press, timeout)
    end
  end

  defp attempt(press, timeout) do
    result = press.()
    if accepted?(result), do: await_touches(timeout), else: injection_skip(result)
  end

  # touch_stop/0 must answer too: it is the half that restores the window.
  defp combine(:pass, :ok), do: :pass
  defp combine(:pass, other), do: classify_nif("touch_stop/0", other)
  defp combine(result, _stop), do: result

  @doc false
  # Whether a press_down_xy result means the down reached the window.
  # :dispatch_failed only says no view consumed it (the bridge then cancels
  # the pointer itself); the observer sees both events first.
  @spec accepted?(term()) :: boolean()
  def accepted?(:ok), do: true
  def accepted?({:error, :dispatch_failed}), do: true
  def accepted?(_), do: false

  @doc false
  @spec injection_skip(term()) :: Mob.Plugin.SelfTest.result()
  def injection_skip(result) do
    {:skip,
     "touch_start/1 answered :ok, but this host cannot inject a touch to observe " <>
       "(:mob_nif.press_down_xy/3 returned #{inspect(result)})"}
  end

  @doc false
  # What the NIF answered instead of :ok.
  @spec classify_nif(String.t(), term()) :: Mob.Plugin.SelfTest.result()
  def classify_nif(call, {:error, :bridge_not_registered}) do
    {:fail,
     "#{call}: Kotlin MobTouchBridge not registered " <>
       "(nativeRegister never ran or a method-ID lookup failed)"}
  end

  def classify_nif(call, other), do: {:fail, "#{call} returned #{inspect(other)}, expected :ok"}

  @doc false
  # The classification of what the observer delivers for one injected press:
  # a :down, then the pointer's end (:cancel, or :up), at the injected point.
  @spec await_touches(non_neg_integer()) :: Mob.Plugin.SelfTest.result()
  def await_touches(timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    collect(deadline, timeout, :down)
  end

  defp collect(deadline, timeout, waiting_for) do
    wait = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:touch, %{phase: phase, x: x, y: y}} when phase in [:down, :up, :cancel] ->
        cond do
          not (near?(x, @x) and near?(y, @y)) ->
            {:fail,
             "observed #{phase} at (#{inspect(x)}, #{inspect(y)}), injected at " <>
               "(#{@x}, #{@y}) dp: the bridge is not converting pixels to dp"}

          waiting_for == :down and phase == :down ->
            collect(deadline, timeout, :end)

          waiting_for == :end and phase in [:up, :cancel] ->
            :pass

          true ->
            collect(deadline, timeout, waiting_for)
        end

      {:touch, %{phase: :move}} ->
        collect(deadline, timeout, waiting_for)

      {:touch, other} ->
        {:fail, "observer delivered #{inspect(other)}, expected %{phase:, x:, y:, ...}"}
    after
      wait ->
        missing = if waiting_for == :down, do: ":down", else: ":cancel / :up after the :down"

        {:fail,
         "injected a touch at (#{@x}, #{@y}) dp but the observer delivered no " <>
           "#{missing} within #{timeout} ms: MobTouchBridge has no Activity or its " <>
           "Window.Callback proxy is not installed"}
    end
  end

  defp near?(v, want) when is_number(v), do: abs(v - want) <= 1.0
  defp near?(_, _want), do: false
end
