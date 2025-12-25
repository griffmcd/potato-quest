defmodule PotatoQuestServer.Game.PlayerSession do
  @moduledoc """
  GenServer that manages individual player state.
  Each connected player has their own PlayerSession process.
  """
  use GenServer

  require Logger

  # Client API

  def start_link(opts) do
    player_id = Keyword.fetch!(opts, :player_id)
    username = Keyword.fetch!(opts, :username)

    GenServer.start_link(__MODULE__, %{
      player_id: player_id,
      username: username
    }, name: via_tuple(player_id))
  end

  def get_state(player_id) do
    GenServer.call(via_tuple(player_id), :get_state)
  end

  def update_position(player_id, position) do
    GenServer.cast(via_tuple(player_id), {:update_position, position})
  end

  def get_position(player_id) do
    GenServer.call(via_tuple(player_id), :get_position)
  end

  def add_gold(player_id, amount) do
    GenServer.call(via_tuple(player_id), {:add_gold, amount})
  end

  # Server Callbacks

  @impl true
  def init(args) do
    Logger.info("Starting PlayerSession for #{args.username} (#{args.player_id})")

    state = %{
      player_id: args.player_id,
      username: args.username,
      position: %{x: 0, y: 0, z: 0, zone_id: "spawn_town"},
      stats: %{
        health: 100,
        max_health: 100,
        stamina: 100,
        max_stamina: 100,
        mana: 50,
        max_mana: 50,
        str: 10,
        dex: 10,
        int: 10
      },
      inventory: [],
      equipment: %{
        head: nil,
        chest: nil,
        legs: nil,
        weapon: nil,
        shield: nil
      },
      gold: 0,
      connected: true
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:get_position, _from, state) do
    {:reply, state.position, state}
  end

  @impl true
  def handle_call({:add_gold, amount}, _from, state) do
    new_gold = state.gold + amount
    Logger.info("Player #{state.username} received #{amount} gold (total: #{new_gold})")
    {:reply, :ok, %{state | gold: new_gold}}
  end

  @impl true
  def handle_cast({:update_position, position}, state) do
    new_position = Map.merge(state.position, position)
    {:noreply, %{state | position: new_position}}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("PlayerSession terminating for #{state.username}: #{inspect(reason)}")
    :ok
  end

  # Private Functions

  defp via_tuple(player_id) do
    {:via, Registry, {PotatoQuestServer.Game.PlayerRegistry, player_id}}
  end
end
