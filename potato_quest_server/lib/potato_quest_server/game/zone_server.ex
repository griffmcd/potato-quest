defmodule PotatoQuestServer.Game.ZoneServer do
  @moduledoc """
  GenServer that manages a single zone (town or wilderness instance).
  Tracks players, enemies, and items in the zone.
  """
  use GenServer

  require Logger

  # Client API

  def start_link(opts) do
    zone_id = Keyword.fetch!(opts, :zone_id)
    GenServer.start_link(__MODULE__, %{zone_id: zone_id}, name: via_tuple(zone_id))
  end

  def player_entered(zone_id, player_id, username) do
    GenServer.call(via_tuple(zone_id), {:player_entered, player_id, username})
  end

  def player_left(zone_id, player_id) do
    GenServer.cast(via_tuple(zone_id), {:player_left, player_id})
  end

  def get_players(zone_id) do
    GenServer.call(via_tuple(zone_id), :get_players)
  end

  # Server Callbacks

  @impl true
  def init(args) do
    Logger.info("Starting ZoneServer for #{args.zone_id}")

    state = %{
      zone_id: args.zone_id,
      zone_type: :town, # :town or :wilderness
      players: %{}, # %{player_id => %{username, position}}
      enemies: [],
      items: [],
      seed: :rand.uniform(1_000_000)
    }

    # For now, we won't start a tick loop
    # We'll add that when we implement enemy AI

    {:ok, state}
  end

  @impl true
  def handle_call({:player_entered, player_id, username}, _from, state) do
    Logger.info("Player #{username} entered zone #{state.zone_id}")

    # Add player to zone
    players = Map.put(state.players, player_id, %{
      username: username,
      position: %{x: 0, y: 0, z: 0}
    })

    new_state = %{state | players: players}

    # Return current zone state to the player
    zone_state = %{
      zone_id: state.zone_id,
      seed: state.seed,
      players: format_players(players)
    }

    {:reply, {:ok, zone_state}, new_state}
  end

  @impl true
  def handle_call(:get_players, _from, state) do
    {:reply, format_players(state.players), state}
  end

  @impl true
  def handle_cast({:player_left, player_id}, state) do
    Logger.info("Player #{player_id} left zone #{state.zone_id}")
    players = Map.delete(state.players, player_id)

    # If zone is empty and it's a wilderness zone, we could shut it down
    # For now, we'll keep it running
    if map_size(players) == 0 do
      Logger.info("Zone #{state.zone_id} is now empty")
    end

    {:noreply, %{state | players: players}}
  end

  # Private Functions

  defp via_tuple(zone_id) do
    {:via, Registry, {PotatoQuestServer.Game.ZoneRegistry, zone_id}}
  end

  defp format_players(players) do
    Enum.map(players, fn {player_id, player_data} ->
      Map.put(player_data, :player_id, player_id)
    end)
  end
end
