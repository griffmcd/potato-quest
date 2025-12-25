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

  def get_enemies(zone_id) do
    GenServer.call(via_tuple(zone_id), :get_enemies)
  end

  def handle_attack(zone_id, player_id, enemy_id) do
    GenServer.call(via_tuple(zone_id), {:attack, player_id, enemy_id})
  end

  def handle_pickup(zone_id, player_id, item_id) do
    GenServer.call(via_tuple(zone_id), {:pickup_item, player_id, item_id})
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
      seed: :rand.uniform(1_000_000),
      enemy_counter: 0,
      item_counter: 0,
      tick_ref: nil
    }
    test_enemy = %{
      id: "enemy_0",
      type: :pig_man,
      position: %{x: 5.0, y: 0.0, z: 0.0},
      health: 50,
      max_health: 50,
      state: :alive
    }

    tick_ref = schedule_world_tick()

    {:ok, %{ state |
      enemies: [test_enemy],
      enemy_counter: 1,
      tick_ref: tick_ref
    }}
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
  def handle_call({:attack, player_id, enemy_id}, _from, state) do
    case find_enemy(state.enemies, enemy_id) do
      nil ->
        {:reply, {:error, :enemy_not_found}, state}
      enemy ->
        player_state  = PotatoQuestServer.Game.PlayerSession.get_state(player_id)
        damage = calculate_damage(player_state.stats)
        new_health = max(0, enemy.health - damage)
        updated_enemy = %{enemy | health: new_health}
        enemies = update_enemy(state.enemies, updated_enemy)

        if new_health == 0 do
          {loot_item, new_counter} = spawn_loot(enemy, state.item_counter)
          new_state = %{state |
            enemies: mark_enemy_dead(enemies, enemy_id),
            items: [loot_item | state.items],
            item_counter: new_counter
          }
          {:reply, {:ok, {:enemy_died, damage, loot_item}}, new_state}
        else
          {:reply, {:ok, {:enemy_damaged, damage, new_health}},
            %{state | enemies: enemies }}
        end
    end
  end

  @impl true
  def handle_call({:pickup_item, player_id, item_id}, _from, state) do
    case find_item(state.items, item_id) do
      nil -> {:reply, {:error, :item_not_found}, state}
      item ->
        items = remove_item(state.items, item_id)
        PotatoQuestServer.Game.PlayerSession.add_gold(player_id, item.value)
        {:reply, {:ok, item}, %{state | items: items}}
    end
  end

  @impl true
  def handle_call(:get_enemies, _from, state) do
    {:reply, state.enemies, state}
  end

  @impl true
  def handle_info(:world_tick, state) do
    tick_ref = schedule_world_tick()
    {:noreply, %{state | tick_ref: tick_ref }}
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

  defp schedule_world_tick do
    Process.send_after(self(), :world_tick, 200) # 5 ticks/sec
  end

  defp calculate_damage(stats) do
    stats.str * 2
  end

  defp spawn_loot(enemy, counter) do
    item = %{
      id: "item_#{counter}",
      item_type: :gold_coin,
      position: enemy.position,
      value: 10
    }
    {item, counter + 1}
  end

  defp find_enemy(enemies, enemy_id) do
    Enum.find(enemies, fn e -> e.id == enemy_id && e.state == :alive end)
  end

  defp update_enemy(enemies, updated_enemy) do
    Enum.map(enemies, fn e ->
      if e.id == updated_enemy.id, do: updated_enemy, else: e
    end)
  end

  defp mark_enemy_dead(enemies, enemy_id) do
    Enum.map(enemies, fn e ->
      if e.id == enemy_id, do: %{e | state: :dead}, else: e
    end)
  end

  defp find_item(items, item_id) do
    Enum.find(items, fn i -> i.id == item_id end)
  end

  defp remove_item(items, item_id) do
    Enum.reject(items, fn i -> i.id == item_id end)
  end
end
