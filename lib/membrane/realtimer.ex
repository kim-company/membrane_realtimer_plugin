defmodule Membrane.Realtimer do
  @moduledoc """
  Sends buffers to the output in real time, according to buffers' timestamps.

  If buffers come in slower than realtime, they're sent as they come in.
  """
  use Membrane.Filter

  alias Membrane.Buffer

  def_input_pad :input, caps: :any, demand_unit: :buffers
  def_output_pad :output, caps: :any, mode: :push

  @impl true
  def handle_init(_opts) do
    {:ok, %{previous_timestamp: 0, tick_actions: []}}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    {{:ok, start_timer: {:timer, :no_interval}, demand: {:input, 1}}, state}
  end

  @impl true
  def handle_process(:input, buffer, _ctx, state) do
    use Ratio
    interval = Buffer.get_dts_or_pts(buffer) - state.previous_timestamp

    state = %{
      state
      | previous_timestamp: Buffer.get_dts_or_pts(buffer),
        tick_actions: [buffer: {:output, buffer}] ++ state.tick_actions
    }

    {{:ok, timer_interval: {:timer, interval}}, state}
  end

  @impl true
  def handle_event(pad, event, _ctx, %{tick_actions: tick_actions} = state)
      when pad == :output or tick_actions == [] do
    {{:ok, forward: event}, state}
  end

  @impl true
  def handle_event(:input, event, _ctx, state) do
    {:ok, %{state | tick_actions: [event: {:output, event}] ++ state.tick_actions}}
  end

  @impl true
  def handle_caps(:input, caps, _ctx, %{tick_actions: []} = state) do
    {{:ok, forward: caps}, state}
  end

  @impl true
  def handle_caps(:input, caps, _ctx, state) do
    {:ok, %{state | tick_actions: [caps: {:output, caps}] ++ state.tick_actions}}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, %{tick_actions: []} = state) do
    {{:ok, end_of_stream: :output}, state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    {:ok, %{state | tick_actions: [end_of_stream: :output] ++ state.tick_actions}}
  end

  @impl true
  def handle_tick(:timer, _ctx, state) do
    actions =
      [timer_interval: {:timer, :no_interval}] ++
        Enum.reverse(state.tick_actions) ++ [demand: {:input, 1}]

    {{:ok, actions}, %{state | tick_actions: []}}
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state) do
    {{:ok, stop_timer: :timer}, %{state | previous_timestamp: 0}}
  end
end
