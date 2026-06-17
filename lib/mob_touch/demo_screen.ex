defmodule MobTouch.DemoScreen do
  @moduledoc """
  A ready-to-run sample screen exercising `MobTouch`, shipped so a generated app
  can kick the tires the moment the plugin is activated. Declared in the plugin
  manifest's `:screens`. Delete it (and the manifest entry) in a real app.

  Tap **Start**, then drag anywhere on screen: the latest touch's phase and
  coordinates update live, and the button still works — proof the stream
  observes without consuming.
  """
  use Mob.Screen

  @impl true
  def mount(_params, _session, socket) do
    {:ok, Mob.Socket.assign(socket, streaming: false, last: nil, count: 0)}
  end

  @impl true
  def render(assigns) do
    ~MOB"""
    <Column background={:background} padding={:space_lg} fill_width={true} fill_height={true}>
      <Text text="Touch" text_size={:lg} text_color={:on_surface} padding={:space_sm} />
      <Text text={status_text(assigns)} text_size={:sm} text_color={:primary} padding={4} />
      <Spacer size={8} />
      <Text text={touch_text(assigns)} text_size={:md} text_color={:on_surface} padding={4} />
      <Text text={"events: #{assigns.count}"} text_size={:sm} text_color={:muted} padding={4} />
      <Spacer size={16} />
      <Button text={if(assigns.streaming, do: "Stop", else: "Start")} background={:primary} text_color={:on_primary} padding={:space_md} fill_width={true} on_tap={{self(), :toggle}} />
    </Column>
    """
  end

  defp status_text(%{streaming: true}), do: "Streaming — drag anywhere"
  defp status_text(_), do: "Tap Start, then drag"

  defp touch_text(%{last: nil}), do: "No touch yet"

  defp touch_text(%{last: %{phase: p, x: x, y: y, pointer: ptr}}) do
    "#{p} @ #{Float.round(x, 1)}, #{Float.round(y, 1)} (pointer #{ptr})"
  end

  @impl true
  def handle_info({:tap, :toggle}, %{assigns: %{streaming: true}} = socket) do
    {:noreply, MobTouch.stop(socket) |> Mob.Socket.assign(streaming: false)}
  end

  def handle_info({:tap, :toggle}, socket) do
    {:noreply, MobTouch.start(socket) |> Mob.Socket.assign(streaming: true)}
  end

  def handle_info({:touch, info}, socket) do
    {:noreply, Mob.Socket.assign(socket, last: info, count: socket.assigns.count + 1)}
  end
end
