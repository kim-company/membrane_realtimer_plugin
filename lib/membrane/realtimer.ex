defmodule Membrane.Realtimer do
  @moduledoc """
  Sends buffers to the output in real time, according to buffers' timestamps.

  If buffers come in slower than realtime, they're sent as they come in.
  """
  use Membrane.Filter

  alias Membrane.Buffer

  def_input_pad :input, accepted_format: _any, demand_unit: :buffers
  def_output_pad :output, accepted_format: _any, mode: :push

  def_options(
    delay: [
      spec: Membrana.Time.t(),
      description: "Delivery delay added before sending each buffer",
      default: 0
    ]
  )

  @impl true
  def handle_init(_ctx, opts) do
    {[], %{previous_timestamp: nil, tick_actions: [], delay: opts.delay}}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[demand: {:input, 1}], state}
  end

  # TODO: remove when https://github.com/membraneframework/membrane_core/pull/502 is merged and released
  @dialyzer {:no_behaviours, {:handle_process, 4}}
  @impl true
  def handle_process(:input, buffer, ctx, %{previous_timestamp: nil} = state) do
    {actions, state} =
      handle_process(:input, buffer, ctx, %{
        state
        | previous_timestamp: (Buffer.get_dts_or_pts(buffer) || 0) - state.delay
      })

    {[{:start_timer, {:timer, :no_interval}} | actions], state}
  end

  def handle_process(:input, buffer, _ctx, state) do
    use Ratio
    interval = Buffer.get_dts_or_pts(buffer) - state.previous_timestamp

    state = %{
      state
      | previous_timestamp: Buffer.get_dts_or_pts(buffer),
        tick_actions: [buffer: {:output, buffer}] ++ state.tick_actions
    }

    {[timer_interval: {:timer, interval}], state}
  end

  @impl true
  def handle_event(pad, event, _ctx, %{tick_actions: tick_actions} = state)
      when pad == :output or tick_actions == [] do
    {[forward: event], state}
  end

  @impl true
  def handle_event(:input, event, _ctx, state) do
    {[], %{state | tick_actions: [event: {:output, event}] ++ state.tick_actions}}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, %{tick_actions: []} = state) do
    {[forward: stream_format], state}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    {[], %{state | tick_actions: [stream_format: {:output, stream_format}] ++ state.tick_actions}}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, %{tick_actions: []} = state) do
    {[end_of_stream: :output], state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    {[], %{state | tick_actions: [end_of_stream: :output] ++ state.tick_actions}}
  end

  @impl true
  def handle_tick(:timer, _ctx, state) do
    actions =
      [timer_interval: {:timer, :no_interval}] ++
        Enum.reverse(state.tick_actions) ++ [demand: {:input, 1}]

    {actions, %{state | tick_actions: []}}
  end

  @impl true
  def handle_parent_notification(
        {:delay, delay},
        _ctx,
        state
      ) do
    state =
      state
      |> update_in([:previous_timestamp], fn
        nil -> nil
        # undo the previously applied delay before adding the new one
        previous -> previous + state.delay - delay
      end)
      |> put_in([:delay], delay)

    {[], state}
  end
end
