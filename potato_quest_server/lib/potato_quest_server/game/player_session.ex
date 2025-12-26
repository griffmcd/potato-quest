defmodule PotatoQuestServer.Game.PlayerSession do
  @moduledoc """
  GenServer that manages individual player state.
  Each connected player has their own PlayerSession process.
  """
  use GenServer

  alias PotatoQuestServer.Game.ItemCatalog, as: ItemCatalog

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

  def equip_item(player_id, instance_id) do
    GenServer.call(via_tuple(player_id), {:equip_item, instance_id})
  end

  def unequip_item(player_id, slot) do
    GenServer.call(via_tuple(player_id), {:unequip_item, slot})
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
        str: 0,
        def: 0,
        dex: 0,
        int: 0,
        damage: 0,

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
    state = recalculate_stats(state)

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

  @impl true
  def handle_call({:equip_item, instance_id}, _from, state) do
    case find_and_remove_item(state.inventory, instance_id) do
      {:error, reason} ->
        {:reply, {:error, reason}, state}
      {:ok, item_instance, new_inventory} ->
        # get item template to determine what slot it goes in
        item_template = ItemCatalog.get_item(item_instance.template_id)
        slot = item_template.slot
        case state.equipment[slot] do
          nil ->
            new_equipment = Map.put(state.equipment, slot, item_instance)
            new_state = %{state | equipment: new_equipment, inventory: new_inventory}
            new_state = recalculate_stats(new_state)
            {:reply, {:ok, new_state.equipment, new_state.stats}, new_state}
          _occupied ->
            {:reply, {:error, :slot_occupied}, state}
        end
    end
  end

  @impl true
  def handle_call({:unequip_item, slot}, _from, state) do
    case state.equipment[slot] do
      nil ->
        {:reply, {:error, :slot_empty}, state}
      equipped_item ->
        case find_empty_slot(state.inventory) do
          nil -> {:reply, {:error, :inventory_full}, state}
          slot_num ->
            new_equipment = Map.put(state.equipment, slot, nil)
            inventory_item = %{
              slot: slot_num,
              instance_id: equipped_item.instance_id,
              template_id: equipped_item.template_id
            }
            new_inventory = [inventory_item | state.inventory]
            new_state = %{state | equipment: new_equipment, inventory: new_inventory}
            new_state = recalculate_stats(new_state)
            {:reply, {:ok, new_state.equipment, new_state.stats}, new_state}
        end
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

  defp calculate_equipment_bonuses(equipment) do
    Enum.reduce(equipment, %{
      str_bonus: 0,
      def_bonus: 0,
      dex_bonus: 0,
      int_bonus: 0},
      fn {_slot, equipped_item}, acc ->
        case equipped_item do
          nil -> acc
          item_instance ->
            item = ItemCatalog.get_item(item_instance.template_id)
            %{
              str_bonus: acc.str_bonus + item.stats.str_bonus,
              def_bonus: acc.def_bonus + item.stats.def_bonus,
              dex_bonus: acc.dex_bonus + item.stats.dex_bonus,
              int_bonus: acc.int_bonus + item.stats.int_bonus
            }
        end
      end)
  end

  defp recalculate_stats(state) do
    equipment_bonuses = calculate_equipment_bonuses(state.equipment)
    weapon_damage = if state.equipment.weapon do
      item = ItemCatalog.get_item(state.equipment.weapon.template_id)
      item.stats.damage
    else
      0
    end

    total_str = state.stats.base_str + equipment_bonuses.str_bonus
    total_def = state.stats.base_def + equipment_bonuses.def_bonus
    total_dex = state.stats.base_dex + equipment_bonuses.dex_bonus
    total_int = state.stats.base_int + equipment_bonuses.int_bonus
    total_damage = weapon_damage + (total_str * 2)

    updated_stats = Map.merge(state.stats, %{
      str: total_str,
      def: total_def,
      dex: total_dex,
      int: total_int,
      damage: total_damage
    })
    %{state | stats: updated_stats }
  end

  defp generate_instance_id do
    "item_#{System.unique_integer([:positive])}"
  end
end
