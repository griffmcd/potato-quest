defmodule PotatoQuestServer.Game.PlayerSessionTest do
  use PotatoQuestServer.GenServerCase, async: true

  alias PotatoQuestServer.Game.PlayerSession

  # Helper to create unique player IDs per test
  defp unique_player_id, do: "test_player_#{System.unique_integer([:positive])}"

  describe "start_link/1" do
    test "starts and registers a player session with required opts" do
      player_id = unique_player_id()

      {:ok, pid} =
        start_supervised({PlayerSession, player_id: player_id, username: "test_user"})

      assert Process.alive?(pid)

      # Verify registration
      [{^pid, _}] = Registry.lookup(PotatoQuestServer.Game.PlayerRegistry, player_id)
    end

    test "initializes state with correct player_id and username" do
      player_id = unique_player_id()
      start_supervised({PlayerSession, player_id: player_id, username: "test_user"})

      state = PlayerSession.get_state(player_id)
      assert state.player_id == player_id
      assert state.username == "test_user"
    end

    test "initializes state with default position (spawn_town)" do
      player_id = unique_player_id()
      start_supervised({PlayerSession, player_id: player_id, username: "test_user"})

      state = PlayerSession.get_state(player_id)
      assert state.position.x == 0
      assert state.position.y == 0
      assert state.position.z == 0
      assert state.position.zone_id == "spawn_town"
    end

    test "initializes inventory with starting items (bronze_sword, wooden_shield)" do
      player_id = unique_player_id()
      start_supervised({PlayerSession, player_id: player_id, username: "test_user"})

      state = PlayerSession.get_state(player_id)
      assert length(state.inventory) == 2
      assert Enum.any?(state.inventory, fn item -> item.template_id == "bronze_sword" end)
      assert Enum.any?(state.inventory, fn item -> item.template_id == "wooden_shield" end)
    end

    test "initializes gold to 30" do
      player_id = unique_player_id()
      start_supervised({PlayerSession, player_id: player_id, username: "test_user"})

      state = PlayerSession.get_state(player_id)
      assert state.gold == 30
    end

    test "initializes connected to true" do
      player_id = unique_player_id()
      start_supervised({PlayerSession, player_id: player_id, username: "test_user"})

      state = PlayerSession.get_state(player_id)
      assert state.connected == true
    end

    test "initializes stats with base and calculated values" do
      player_id = unique_player_id()
      start_supervised({PlayerSession, player_id: player_id, username: "test_user"})

      state = PlayerSession.get_state(player_id)
      assert state.stats.base_str == 10
      assert state.stats.base_def == 5
      assert state.stats.base_dex == 10
      assert state.stats.base_int == 10
      assert state.stats.str == 15
      assert state.stats.def == 5
    end

    test "initializes equipment with bronze_sword as weapon" do
      player_id = unique_player_id()
      start_supervised({PlayerSession, player_id: player_id, username: "test_user"})

      state = PlayerSession.get_state(player_id)
      assert state.equipment.weapon != nil
      assert state.equipment.weapon.template_id == "bronze_sword"
    end

    test "fails when player_id is missing from opts" do
      assert_raise KeyError, fn ->
        PlayerSession.start_link(username: "test_user")
      end
    end

    test "fails when username is missing from opts" do
      player_id = unique_player_id()

      assert_raise KeyError, fn ->
        PlayerSession.start_link(player_id: player_id)
      end
    end
  end

  describe "get_state/1" do
    setup do
      player_id = unique_player_id()
      start_supervised({PlayerSession, player_id: player_id, username: "test_user"})
      %{player_id: player_id}
    end

    test "returns the complete player state", %{player_id: player_id} do
      state = PlayerSession.get_state(player_id)
      assert is_map(state)
    end

    test "state contains all expected top-level keys", %{player_id: player_id} do
      state = PlayerSession.get_state(player_id)
      assert Map.has_key?(state, :player_id)
      assert Map.has_key?(state, :username)
      assert Map.has_key?(state, :position)
      assert Map.has_key?(state, :inventory)
      assert Map.has_key?(state, :stats)
      assert Map.has_key?(state, :equipment)
      assert Map.has_key?(state, :gold)
      assert Map.has_key?(state, :connected)
    end
  end

  describe "position management" do
    setup do
      player_id = unique_player_id()
      start_supervised({PlayerSession, player_id: player_id, username: "test_user"})
      %{player_id: player_id}
    end

    test "get_position/1 returns current position", %{player_id: player_id} do
      position = PlayerSession.get_position(player_id)
      assert position.x == 0
      assert position.y == 0
      assert position.z == 0
      assert position.zone_id == "spawn_town"
    end

    test "update_position/1 updates x, y, z coordinates", %{player_id: player_id} do
      PlayerSession.update_position(player_id, %{x: 10, y: 5, z: 3})

      # Wait a bit for async cast to complete
      Process.sleep(10)

      position = PlayerSession.get_position(player_id)
      assert position.x == 10
      assert position.y == 5
      assert position.z == 3
    end

    test "update_position/1 merges with existing position (doesn't replace zone_id)", %{
      player_id: player_id
    } do
      PlayerSession.update_position(player_id, %{x: 15})

      # Wait a bit for async cast to complete
      Process.sleep(10)

      position = PlayerSession.get_position(player_id)
      assert position.x == 15
      assert position.y == 0
      assert position.z == 0
      assert position.zone_id == "spawn_town"
    end

    test "update_position/1 is async (returns immediately)", %{player_id: player_id} do
      result = PlayerSession.update_position(player_id, %{x: 20})
      assert result == :ok
    end
  end

  describe "gold management" do
    setup do
      player_id = unique_player_id()
      start_supervised({PlayerSession, player_id: player_id, username: "test_user"})
      %{player_id: player_id}
    end

    test "add_gold/1 increases gold by specified amount", %{player_id: player_id} do
      PlayerSession.add_gold(player_id, 50)
      state = PlayerSession.get_state(player_id)
      assert state.gold == 80
    end

    test "add_gold/1 with 100 increases gold from 30 to 130", %{player_id: player_id} do
      PlayerSession.add_gold(player_id, 100)
      state = PlayerSession.get_state(player_id)
      assert state.gold == 130
    end

    test "add_gold/1 returns :ok", %{player_id: player_id} do
      result = PlayerSession.add_gold(player_id, 25)
      assert result == :ok
    end
  end

  describe "inventory management - add_item" do
    setup do
      player_id = unique_player_id()
      start_supervised({PlayerSession, player_id: player_id, username: "test_user"})
      %{player_id: player_id}
    end

    test "add_item/1 adds item to first empty slot (slot 2)", %{player_id: player_id} do
      {:ok, new_item} = PlayerSession.add_item(player_id, "leather_tunic")

      assert new_item.slot == 2
      assert new_item.template_id == "leather_tunic"
      assert String.starts_with?(new_item.instance_id, "item_")
    end

    test "add_item/1 returns {:ok, new_item} with instance_id and template_id", %{
      player_id: player_id
    } do
      result = PlayerSession.add_item(player_id, "iron_band")
      assert {:ok, new_item} = result
      assert Map.has_key?(new_item, :instance_id)
      assert Map.has_key?(new_item, :template_id)
      assert Map.has_key?(new_item, :slot)
    end

    test "add_item/1 fills slots sequentially (0,1 occupied -> slot 2, then 3, etc)", %{
      player_id: player_id
    } do
      {:ok, item1} = PlayerSession.add_item(player_id, "leather_tunic")
      {:ok, item2} = PlayerSession.add_item(player_id, "iron_band")
      {:ok, item3} = PlayerSession.add_item(player_id, "leather_tunic")

      assert item1.slot == 2
      assert item2.slot == 3
      assert item3.slot == 4
    end

    test "add_item/1 returns {:error, :inventory_full} when all 28 slots occupied", %{
      player_id: player_id
    } do
      # Fill inventory (already has 2 items, need 26 more)
      Enum.each(1..26, fn _ ->
        PlayerSession.add_item(player_id, "leather_tunic")
      end)

      # 28th slot filled, 29th should fail
      assert {:error, :inventory_full} = PlayerSession.add_item(player_id, "bronze_sword")

      # Verify inventory still has exactly 28 items
      state = PlayerSession.get_state(player_id)
      assert length(state.inventory) == 28
    end

    test "generated instance_ids are unique across multiple add_item calls", %{
      player_id: player_id
    } do
      {:ok, item1} = PlayerSession.add_item(player_id, "leather_tunic")
      {:ok, item2} = PlayerSession.add_item(player_id, "iron_band")
      {:ok, item3} = PlayerSession.add_item(player_id, "leather_tunic")

      assert item1.instance_id != item2.instance_id
      assert item2.instance_id != item3.instance_id
      assert item1.instance_id != item3.instance_id
    end
  end

  describe "inventory management - unequip_item" do
    setup do
      player_id = unique_player_id()
      start_supervised({PlayerSession, player_id: player_id, username: "test_user"})
      %{player_id: player_id}
    end

    test "unequip_item/2 removes an item from an equipment slot", %{player_id: player_id} do
      {:ok, new_equipment, new_stats} = PlayerSession.unequip_item(player_id, :weapon)
      assert new_equipment.weapon == nil
      assert new_stats.str == 10
      assert new_stats.damage == 20
    end

    test "unequip_item/2 returns the unequipped item to inventory", %{player_id: player_id} do
      initial_state = PlayerSession.get_state(player_id)
      initial_count = length(initial_state.inventory)
      equipped_weapon = initial_state.equipment.weapon
      PlayerSession.unequip_item(player_id, :weapon)
      final_state = PlayerSession.get_state(player_id)
      assert length(final_state.inventory) == initial_count + 1
      assert Enum.any?(final_state.inventory, fn item -> item.instance_id == equipped_weapon.instance_id end)
    end

    test "unequip_item/2 returns error when item not equipped", %{player_id: player_id} do
      {:error, error_type} = PlayerSession.unequip_item(player_id, :shield)
      assert error_type == :slot_empty
    end

    test "unequip_item/2 returns error when inventory is full", %{player_id: player_id} do
      Enum.each(1..26, fn _ ->
        PlayerSession.add_item(player_id, "leather_tunic")
      end)
      {:error, error_type} = PlayerSession.unequip_item(player_id, :weapon)
      assert error_type == :inventory_full
    end
  end

  describe "inventory management - equip_item" do
    setup do
      player_id = unique_player_id()
      start_supervised({PlayerSession, player_id: player_id, username: "test_user"})
      %{player_id: player_id}
    end

    test "equip_item/2 equips an item in an empty equipment slot", %{player_id: player_id} do
      # get wooden shield instance_id from inventory
      state = PlayerSession.get_state(player_id)
      shield_item = Enum.find(state.inventory, fn item -> item.template_id == "wooden_shield" end)
      {:ok, new_equipment, new_stats} = PlayerSession.equip_item(player_id, shield_item.instance_id)
      assert new_equipment.shield != nil
      assert new_equipment.shield.template_id == "wooden_shield"
      assert new_equipment.shield.instance_id == shield_item.instance_id
      assert new_stats.def == 8
    end

    test "equip_item/2 returns error when slot is occupied", %{player_id: player_id} do
      state = PlayerSession.get_state(player_id)
      sword_item = Enum.find(state.inventory, fn item -> item.template_id == "bronze_sword" end)
      {:error, error_type} = PlayerSession.equip_item(player_id, sword_item.instance_id)
      assert error_type == :slot_occupied
    end

    test "equip_item/2 returns error for non-existent instance_id", %{player_id: player_id} do
      {:error, error_type} = PlayerSession.equip_item(player_id, "nonexistent_item_id")
      assert error_type == :item_not_found
    end

    test "equip_item/2 removes item from inventory after equipping", %{player_id: player_id} do
      initial_state = PlayerSession.get_state(player_id)
      initial_count = length(initial_state.inventory)
      shield_item = Enum.find(initial_state.inventory, fn item -> item.template_id == "wooden_shield" end)
      PlayerSession.equip_item(player_id, shield_item.instance_id)
      final_state = PlayerSession.get_state(player_id)
      assert length(final_state.inventory) == initial_count - 1
      refute Enum.any?(final_state.inventory, fn item -> item.instance_id == shield_item.instance_id end)
    end
  end

  describe "inventory management - remove_item" do
    setup do
      player_id = unique_player_id()
      start_supervised({PlayerSession, player_id: player_id, username: "test_user"})
      %{player_id: player_id}
    end

    test "remove_item/1 removes item by instance_id and returns item", %{player_id: player_id} do
      {:ok, added_item} = PlayerSession.add_item(player_id, "leather_tunic")
      {:ok, removed_item} = PlayerSession.remove_item(player_id, added_item.instance_id)

      assert removed_item.instance_id == added_item.instance_id
      assert removed_item.template_id == "leather_tunic"
    end

    test "remove_item/1 returns {:error, :item_not_found} for non-existent instance_id", %{
      player_id: player_id
    } do
      result = PlayerSession.remove_item(player_id, "non_existent_item")
      assert {:error, :item_not_found} = result
    end

    test "remove_item/1 frees up the slot for future items", %{player_id: player_id} do
      {:ok, item1} = PlayerSession.add_item(player_id, "leather_tunic")
      slot_num = item1.slot

      PlayerSession.remove_item(player_id, item1.instance_id)

      {:ok, item2} = PlayerSession.add_item(player_id, "iron_band")

      # Should reuse the freed slot
      assert item2.slot == slot_num
    end

    test "removing an item updates inventory list correctly", %{player_id: player_id} do
      {:ok, item1} = PlayerSession.add_item(player_id, "leather_tunic")
      initial_state = PlayerSession.get_state(player_id)
      initial_count = length(initial_state.inventory)

      PlayerSession.remove_item(player_id, item1.instance_id)

      final_state = PlayerSession.get_state(player_id)
      assert length(final_state.inventory) == initial_count - 1
      refute Enum.any?(final_state.inventory, fn item -> item.instance_id == item1.instance_id end)
    end
  end

  describe "inventory management - drop_item" do
    setup do
      player_id = unique_player_id()
      zone_id = "test_zone_#{System.unique_integer([:positive])}"

      start_supervised({PlayerSession, player_id: player_id, username: "test_user"})

      # Start a ZoneServer for the zone so drop_item doesn't fail
      start_supervised({PotatoQuestServer.Game.ZoneServer, zone_id: zone_id})

      # Update player position to be in that zone
      PlayerSession.update_position(player_id, %{zone_id: zone_id})
      Process.sleep(10)

      %{player_id: player_id, zone_id: zone_id}
    end

    test "drop_item/1 removes item from inventory", %{player_id: player_id} do
      {:ok, item} = PlayerSession.add_item(player_id, "leather_tunic")
      initial_state = PlayerSession.get_state(player_id)
      initial_count = length(initial_state.inventory)

      {:ok, _} = PlayerSession.drop_item(player_id, item.instance_id)

      final_state = PlayerSession.get_state(player_id)
      assert length(final_state.inventory) == initial_count - 1
    end

    test "drop_item/1 returns {:ok, item_instance}", %{player_id: player_id} do
      {:ok, item} = PlayerSession.add_item(player_id, "iron_band")
      result = PlayerSession.drop_item(player_id, item.instance_id)

      assert {:ok, dropped_item} = result
      assert dropped_item.instance_id == item.instance_id
    end

    test "drop_item/1 returns {:error, :item_not_found} for non-existent item", %{
      player_id: player_id
    } do
      result = PlayerSession.drop_item(player_id, "non_existent_item")
      assert {:error, :item_not_found} = result
    end
  end

  describe "GenServer lifecycle" do
    test "process can be looked up via Registry with player_id" do
      player_id = unique_player_id()
      {:ok, pid} = start_supervised({PlayerSession, player_id: player_id, username: "test_user"})

      case Registry.lookup(PotatoQuestServer.Game.PlayerRegistry, player_id) do
        [{^pid, _}] -> assert true
        _ -> flunk("Process not registered correctly")
      end
    end
  end

  describe "stat calculation" do
    test "initializes with correct calculated stats based on equipped weapon" do
      player_id = unique_player_id()
      start_supervised({PlayerSession, player_id: player_id, username: "test_user"})

      state = PlayerSession.get_state(player_id)
      # player starts with bronze_sword equipped (damage: 15, str_bonus: 5)
      assert state.stats.str == 15
      assert state.stats.def == 5

      # damage = weapon.damage (15) + (total_str (15) * 2) = 45
      assert state.stats.damage == 45
    end

    test "base stats never change" do
      player_id = unique_player_id()
      start_supervised({PlayerSession, player_id: player_id, username: "test_user"})

      state = PlayerSession.get_state(player_id)
      assert state.stats.base_str == 10
      assert state.stats.base_def == 5
      assert state.stats.base_dex == 10
      assert state.stats.base_int == 10
    end
  end
end
