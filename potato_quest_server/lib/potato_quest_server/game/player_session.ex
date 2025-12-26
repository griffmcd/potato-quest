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

  def add_item(player_id, template_id) do
    GenServer.call(via_tuple(player_id), {:add_item, template_id})
  end

  def remove_item(player_id, instance_id) do
    GenServer.call(via_tuple(player_id), {:remove_item, instance_id})
  end

  def drop_item(player_id, instance_id) do
    GenServer.call(via_tuple(player_id), {:drop_item, instance_id})
  end

  # Server Callbacks

  @impl true
  def init(args) do
    Logger.info("Starting PlayerSession for #{args.username} (#{args.player_id})")

    state = %{
      player_id: args.player_id,
      username: args.username,
      position: %{x: 0, y: 0, z: 0, zone_id: "spawn_town"},
      inventory: [
        %{slot: 0, instance_id: "sword_1", template_id: "bronze_sword"},
        %{slot: 1, instance_id: "shield_1", template_id: "wooden_shield"},
      ],
      stats: %{
        # base stats never change
        base_str: 10,
        base_def: 5,
        base_dex: 10,
        base_int: 10,
        base_health: 100,
        base_max_health: 100,
        # calculated stats (base + equipment bonuses)
        # TODO: this should probably not live here forever, but should
        #  actually be calculated
        str: 15,
        def: 8,
        dex: 10,
        int: 10,
        damage: 35,

        health: 100,
        max_health: 100,
        stamina: 100,
        max_stamina: 100,
        mana: 50,
        max_mana: 50,
      },
      equipment: %{
        head: nil,
        chest: nil,
        legs: nil,
        weapon: %{instance_id: "sword_2", template_id: "bronze_sword"},
        shield: nil,
        ring: nil,
        amulet: nil
      },
      gold: 30,
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
  def handle_call({:add_item, item_id}, _from, state) do
    case find_empty_slot(state.inventory) do
      nil -> {:reply, {:error, :inventory_full}, state}
      slot_num ->
        instance_id = generate_instance_id()
        new_item = %{
          slot: slot_num,
          instance_id: instance_id,
          template_id: item_id
        }
        new_inventory = [new_item | state.inventory]
        {:reply, {:ok, new_item}, %{state | inventory: new_inventory }}
    end
  end

  # Removes an item from the inventory. Returns the item instance so things can be done with it (drop, etc)
  @impl true
  def handle_call({:remove_item, instance_id}, _from, state) do
    case find_and_remove_item(state.inventory, instance_id) do
      {:error, reason} ->
        {:reply, {:error, reason}, state}
      {:ok, item_instance, new_inventory} ->
        {:reply, {:ok, item_instance}, %{state | inventory: new_inventory}}
    end
  end

  @impl true
  def handle_call({:drop_item, instance_id}, _from, state) do
    case find_and_remove_item(state.inventory, instance_id) do
      {:error, reason} ->
        {:reply, {:error, reason}, state}
      {:ok, item_instance, new_inventory} ->
        # spawn loot at player's position
        PotatoQuestServer.Game.ZoneServer.spawn_player_dropped_item(
          state.position.zone_id,
          item_instance.template_id,
          state.position
        )
        {:reply, {:ok, item_instance}, %{state | inventory: new_inventory}}
    end
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

  defp find_empty_slot(inventory) do
    occupied_slots = MapSet.new(inventory, fn item -> item.slot end)
    Enum.find(0..27, fn slot -> not MapSet.member?(occupied_slots, slot) end)
  end

  defp find_and_remove_item(inventory, instance_id) do
    item_instance = Enum.find(inventory, fn item -> item.instance_id == instance_id end )
    case item_instance do
      nil -> {:error, :item_not_found}
      found_item ->
        new_inventory = Enum.filter(inventory, fn item -> item.instance_id != instance_id end)
        {:ok, found_item, new_inventory}
    end
  end

  defp generate_instance_id do
    "item_#{System.unique_integer([:positive])}"
  end
end
