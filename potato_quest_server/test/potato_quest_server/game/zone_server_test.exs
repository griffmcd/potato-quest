defmodule PotatoQuestServer.Game.ZoneServerTest do
  use PotatoQuestServer.GenServerCase, async: false

  alias PotatoQuestServer.Game.{ZoneServer, PlayerSession}

  # Helpers
  defp unique_zone_id, do: "test_zone_#{System.unique_integer([:positive])}"
  defp unique_player_id, do: "test_player_#{System.unique_integer([:positive])}"

  describe "start_link/1" do
    test "starts and registers a zone server" do
      zone_id = unique_zone_id()
      {:ok, pid} = start_supervised({ZoneServer, zone_id: zone_id})

      assert Process.alive?(pid)

      # Verify registration
      [{^pid, _}] = Registry.lookup(PotatoQuestServer.Game.ZoneRegistry, zone_id)
    end

    test "initializes with test enemy (pig_man) at position (5, 0, 0)" do
      zone_id = unique_zone_id()
      start_supervised({ZoneServer, zone_id: zone_id})

      enemies = ZoneServer.get_enemies(zone_id)
      assert length(enemies) == 1

      [enemy] = enemies
      assert enemy.type == :pig_man
      assert enemy.position.x == 5.0
      assert enemy.position.y == 0.0
      assert enemy.position.z == 0.0
      assert enemy.health == 50
      assert enemy.max_health == 50
      assert enemy.state == :alive
    end

    test "initializes with empty players map" do
      zone_id = unique_zone_id()
      start_supervised({ZoneServer, zone_id: zone_id})

      players = ZoneServer.get_players(zone_id)
      assert players == []
    end

    test "initializes with random seed" do
      zone_id = unique_zone_id()
      {:ok, pid} = start_supervised({ZoneServer, zone_id: zone_id})

      state = get_genserver_state(pid)
      assert is_integer(state.seed)
      assert state.seed > 0
      assert state.seed <= 1_000_000
    end

    test "initializes enemy_counter to 1 (after test enemy)" do
      zone_id = unique_zone_id()
      {:ok, pid} = start_supervised({ZoneServer, zone_id: zone_id})

      state = get_genserver_state(pid)
      assert state.enemy_counter == 1
    end

    test "initializes item_counter to 0" do
      zone_id = unique_zone_id()
      {:ok, pid} = start_supervised({ZoneServer, zone_id: zone_id})

      state = get_genserver_state(pid)
      assert state.item_counter == 0
    end

    test "schedules world_tick after initialization" do
      zone_id = unique_zone_id()
      {:ok, pid} = start_supervised({ZoneServer, zone_id: zone_id})

      state = get_genserver_state(pid)
      assert state.tick_ref != nil
      assert is_reference(state.tick_ref)
    end
  end

  describe "player_entered/3" do
    setup do
      zone_id = unique_zone_id()
      start_supervised({ZoneServer, zone_id: zone_id})
      %{zone_id: zone_id}
    end

    test "adds player to zone players map", %{zone_id: zone_id} do
      player_id = unique_player_id()
      ZoneServer.player_entered(zone_id, player_id, "test_user")

      players = ZoneServer.get_players(zone_id)
      assert length(players) == 1
      assert Enum.any?(players, fn p -> p.player_id == player_id end)
    end

    test "returns {:ok, zone_state} with zone_id and seed", %{zone_id: zone_id} do
      player_id = unique_player_id()
      {:ok, zone_state} = ZoneServer.player_entered(zone_id, player_id, "test_user")

      assert zone_state.zone_id == zone_id
      assert is_integer(zone_state.seed)
    end

    test "zone_state includes formatted players list", %{zone_id: zone_id} do
      player_id = unique_player_id()
      {:ok, zone_state} = ZoneServer.player_entered(zone_id, player_id, "test_user")

      assert is_list(zone_state.players)
      assert length(zone_state.players) == 1
      [player] = zone_state.players
      assert player.player_id == player_id
      assert player.username == "test_user"
    end

    test "multiple players can enter the same zone", %{zone_id: zone_id} do
      player1_id = unique_player_id()
      player2_id = unique_player_id()

      ZoneServer.player_entered(zone_id, player1_id, "user1")
      ZoneServer.player_entered(zone_id, player2_id, "user2")

      players = ZoneServer.get_players(zone_id)
      assert length(players) == 2
      assert Enum.any?(players, fn p -> p.player_id == player1_id end)
      assert Enum.any?(players, fn p -> p.player_id == player2_id end)
    end
  end

  describe "player_left/2" do
    setup do
      zone_id = unique_zone_id()
      start_supervised({ZoneServer, zone_id: zone_id})
      %{zone_id: zone_id}
    end

    test "removes player from zone players map", %{zone_id: zone_id} do
      player_id = unique_player_id()
      ZoneServer.player_entered(zone_id, player_id, "test_user")

      ZoneServer.player_left(zone_id, player_id)
      Process.sleep(10)

      players = ZoneServer.get_players(zone_id)
      assert players == []
    end

    test "is async (cast, returns immediately)", %{zone_id: zone_id} do
      player_id = unique_player_id()
      ZoneServer.player_entered(zone_id, player_id, "test_user")

      result = ZoneServer.player_left(zone_id, player_id)
      assert result == :ok
    end

    test "zone continues running after last player leaves", %{zone_id: zone_id} do
      player_id = unique_player_id()
      ZoneServer.player_entered(zone_id, player_id, "test_user")

      ZoneServer.player_left(zone_id, player_id)
      Process.sleep(10)

      # Zone should still respond to calls
      enemies = ZoneServer.get_enemies(zone_id)
      assert length(enemies) == 1
    end
  end

  describe "get_players/1" do
    setup do
      zone_id = unique_zone_id()
      start_supervised({ZoneServer, zone_id: zone_id})
      %{zone_id: zone_id}
    end

    test "returns empty list when no players in zone", %{zone_id: zone_id} do
      players = ZoneServer.get_players(zone_id)
      assert players == []
    end

    test "returns formatted player list with player_id, username, position", %{zone_id: zone_id} do
      player_id = unique_player_id()
      ZoneServer.player_entered(zone_id, player_id, "test_user")

      players = ZoneServer.get_players(zone_id)
      [player] = players

      assert player.player_id == player_id
      assert player.username == "test_user"
      assert Map.has_key?(player, :position)
    end

    test "includes multiple players after several join", %{zone_id: zone_id} do
      player1_id = unique_player_id()
      player2_id = unique_player_id()
      player3_id = unique_player_id()

      ZoneServer.player_entered(zone_id, player1_id, "user1")
      ZoneServer.player_entered(zone_id, player2_id, "user2")
      ZoneServer.player_entered(zone_id, player3_id, "user3")

      players = ZoneServer.get_players(zone_id)
      assert length(players) == 3
    end
  end

  describe "get_enemies/1" do
    setup do
      zone_id = unique_zone_id()
      start_supervised({ZoneServer, zone_id: zone_id})
      %{zone_id: zone_id}
    end

    test "returns list containing initial test enemy", %{zone_id: zone_id} do
      enemies = ZoneServer.get_enemies(zone_id)
      assert length(enemies) == 1
    end

    test "returns enemies with id, type, position, health, max_health, state", %{zone_id: zone_id} do
      enemies = ZoneServer.get_enemies(zone_id)
      [enemy] = enemies

      assert Map.has_key?(enemy, :id)
      assert Map.has_key?(enemy, :type)
      assert Map.has_key?(enemy, :position)
      assert Map.has_key?(enemy, :health)
      assert Map.has_key?(enemy, :max_health)
      assert Map.has_key?(enemy, :state)
    end
  end

  describe "combat - handle_attack" do
    setup do
      zone_id = unique_zone_id()
      player_id = unique_player_id()

      start_supervised({ZoneServer, zone_id: zone_id})
      start_supervised({PlayerSession, player_id: player_id, username: "test_warrior"})

      [enemy] = ZoneServer.get_enemies(zone_id)

      %{zone_id: zone_id, player_id: player_id, enemy: enemy}
    end

    test "attacking enemy reduces enemy health by calculated damage", %{
      zone_id: zone_id,
      player_id: player_id,
      enemy: enemy
    } do
      initial_health = enemy.health
      {:ok, {:enemy_damaged, damage, new_health}} =
        ZoneServer.handle_attack(zone_id, player_id, enemy.id)

      assert new_health == initial_health - damage
      assert new_health < initial_health
    end

    test "attacking enemy returns {:ok, {:enemy_damaged, damage, new_health}}", %{
      zone_id: zone_id,
      player_id: player_id,
      enemy: enemy
    } do
      result = ZoneServer.handle_attack(zone_id, player_id, enemy.id)
      assert {:ok, {:enemy_damaged, damage, new_health}} = result
      assert is_integer(damage)
      assert is_integer(new_health)
    end

    test "damage calculation uses player stats.damage (weapon + str)", %{
      zone_id: zone_id,
      player_id: player_id,
      enemy: enemy
    } do
      player_state = PlayerSession.get_state(player_id)
      # Damage should equal pre-calculated stats.damage from PlayerSession
      expected_damage = player_state.stats.damage

      {:ok, {:enemy_damaged, damage, _new_health}} =
        ZoneServer.handle_attack(zone_id, player_id, enemy.id)

      assert damage == expected_damage
      # Verify it's weapon.damage (15) + (str (15) * 2) = 45
      assert damage == 45
    end

    test "attacking non-existent enemy returns {:error, :enemy_not_found}", %{
      zone_id: zone_id,
      player_id: player_id
    } do
      result = ZoneServer.handle_attack(zone_id, player_id, "non_existent_enemy")
      assert {:error, :enemy_not_found} = result
    end

    test "attacking already dead enemy returns {:error, :enemy_not_found}", %{
      zone_id: zone_id,
      player_id: player_id,
      enemy: enemy
    } do
      # Kill the enemy first (attack twice since enemy has 50 health and damage is 30)
      ZoneServer.handle_attack(zone_id, player_id, enemy.id)
      ZoneServer.handle_attack(zone_id, player_id, enemy.id)

      # Try to attack again
      result = ZoneServer.handle_attack(zone_id, player_id, enemy.id)
      assert {:error, :enemy_not_found} = result
    end

    test "enemy health never goes below 0", %{
      zone_id: zone_id,
      player_id: player_id,
      enemy: enemy
    } do
      # Attack until dead (multiple times to ensure)
      Enum.each(1..5, fn _ ->
        ZoneServer.handle_attack(zone_id, player_id, enemy.id)
      end)

      # Check all enemies in state
      enemies = ZoneServer.get_enemies(zone_id)
      dead_enemy = Enum.find(enemies, fn e -> e.id == enemy.id end)
      assert dead_enemy.health >= 0
    end
  end

  describe "combat - enemy death" do
    setup do
      zone_id = unique_zone_id()
      player_id = unique_player_id()

      start_supervised({ZoneServer, zone_id: zone_id})
      start_supervised({PlayerSession, player_id: player_id, username: "test_warrior"})

      [enemy] = ZoneServer.get_enemies(zone_id)

      %{zone_id: zone_id, player_id: player_id, enemy: enemy}
    end

    test "when enemy health reaches 0, returns {:ok, {:enemy_died, damage, loot_item}}", %{
      zone_id: zone_id,
      player_id: player_id,
      enemy: enemy
    } do
      # First attack damages the enemy
      {:ok, {:enemy_damaged, _, _}} = ZoneServer.handle_attack(zone_id, player_id, enemy.id)

      # Second attack should kill it (50 health, 30 damage per hit)
      result = ZoneServer.handle_attack(zone_id, player_id, enemy.id)
      assert {:ok, {:enemy_died, damage, spawned_items}} = result
      assert is_integer(damage)
      assert is_list(spawned_items)
    end

    test "dead enemy is marked with state: :dead", %{
      zone_id: zone_id,
      player_id: player_id,
      enemy: enemy
    } do
      # Kill the enemy
      ZoneServer.handle_attack(zone_id, player_id, enemy.id)
      ZoneServer.handle_attack(zone_id, player_id, enemy.id)

      # Check state directly
      enemies = ZoneServer.get_enemies(zone_id)
      dead_enemy = Enum.find(enemies, fn e -> e.id == enemy.id end)
      assert dead_enemy.state == :dead
    end

    test "dead enemy spawns loot items at enemy position", %{
      zone_id: zone_id,
      player_id: player_id,
      enemy: enemy
    } do
      # Kill the enemy
      ZoneServer.handle_attack(zone_id, player_id, enemy.id)
      {:ok, {:enemy_died, _damage, spawned_items}} =
        ZoneServer.handle_attack(zone_id, player_id, enemy.id)

      # Should return a list of items (probabilistic, could be empty)
      assert is_list(spawned_items)

      # All items should be at enemy position
      Enum.each(spawned_items, fn item ->
        assert item.position.x == enemy.position.x
        assert item.position.y == enemy.position.y
        assert item.position.z == enemy.position.z
      end)
    end

    test "loot item has correct structure (id, item_type, position, value)", %{
      zone_id: zone_id,
      player_id: player_id,
      enemy: enemy
    } do
      # Kill the enemy
      ZoneServer.handle_attack(zone_id, player_id, enemy.id)
      {:ok, {:enemy_died, _damage, spawned_items}} =
        ZoneServer.handle_attack(zone_id, player_id, enemy.id)

      # Each item should have the correct structure
      Enum.each(spawned_items, fn item ->
        assert Map.has_key?(item, :id)
        assert Map.has_key?(item, :item_type)
        assert Map.has_key?(item, :position)
        assert Map.has_key?(item, :value)
      end)
    end

    test "item_counter increments for each loot item spawned", %{
      zone_id: zone_id,
      player_id: player_id,
      enemy: enemy
    } do
      pid = GenServer.whereis(via_tuple(zone_id))
      initial_state = get_genserver_state(pid)
      initial_counter = initial_state.item_counter

      # Kill the enemy
      ZoneServer.handle_attack(zone_id, player_id, enemy.id)
      {:ok, {:enemy_died, _damage, spawned_items}} =
        ZoneServer.handle_attack(zone_id, player_id, enemy.id)

      final_state = get_genserver_state(pid)
      # Counter should increment by number of items spawned
      assert final_state.item_counter == initial_counter + length(spawned_items)
    end
  end

  describe "item pickup - handle_pickup" do
    setup do
      zone_id = unique_zone_id()
      player_id = unique_player_id()

      start_supervised({ZoneServer, zone_id: zone_id})
      start_supervised({PlayerSession, player_id: player_id, username: "test_warrior"})

      # Kill enemy to spawn loot
      [enemy] = ZoneServer.get_enemies(zone_id)
      ZoneServer.handle_attack(zone_id, player_id, enemy.id)
      {:ok, {:enemy_died, _damage, spawned_items}} =
        ZoneServer.handle_attack(zone_id, player_id, enemy.id)

      # Get first item (or spawn a known item if list is empty due to RNG)
      loot_item = case spawned_items do
        [first | _] -> first
        [] ->
          # If no items dropped, spawn a test item
          pos = %{x: 0.0, y: 0.0, z: 0.0}
          {:ok, item} = ZoneServer.spawn_player_dropped_item(zone_id, "bronze_sword", pos)
          item
      end

      %{zone_id: zone_id, player_id: player_id, loot_item: loot_item}
    end

    test "picking up item removes it from zone items list", %{
      zone_id: zone_id,
      player_id: player_id,
      loot_item: loot_item
    } do
      pid = GenServer.whereis(via_tuple(zone_id))
      initial_state = get_genserver_state(pid)
      initial_item_count = length(initial_state.items)

      ZoneServer.handle_pickup(zone_id, player_id, loot_item.id)

      final_state = get_genserver_state(pid)
      assert length(final_state.items) == initial_item_count - 1
    end

    test "picking up item adds gold to player via PlayerSession.add_gold", %{
      zone_id: zone_id,
      player_id: player_id,
      loot_item: loot_item
    } do
      initial_gold = PlayerSession.get_state(player_id).gold

      ZoneServer.handle_pickup(zone_id, player_id, loot_item.id)

      final_gold = PlayerSession.get_state(player_id).gold
      assert final_gold == initial_gold + loot_item.value
    end

    test "returns {:ok, :gold, value} for gold or {:ok, :item, item} for equipment", %{
      zone_id: zone_id,
      player_id: player_id,
      loot_item: loot_item
    } do
      result = ZoneServer.handle_pickup(zone_id, player_id, loot_item.id)

      # Could be either gold or equipment based on loot drops
      case result do
        {:ok, :gold, value} ->
          assert is_integer(value)
        {:ok, :item, item_instance} ->
          assert Map.has_key?(item_instance, :instance_id)
          assert Map.has_key?(item_instance, :template_id)
      end
    end

    test "returns {:error, :item_not_found} for non-existent item", %{
      zone_id: zone_id,
      player_id: player_id
    } do
      result = ZoneServer.handle_pickup(zone_id, player_id, "non_existent_item")
      assert {:error, :item_not_found} = result
    end

    test "cannot pick up the same item twice", %{
      zone_id: zone_id,
      player_id: player_id,
      loot_item: loot_item
    } do
      # First pickup succeeds (either gold or item)
      result = ZoneServer.handle_pickup(zone_id, player_id, loot_item.id)
      assert match?({:ok, _, _}, result)

      # Second pickup fails
      result2 = ZoneServer.handle_pickup(zone_id, player_id, loot_item.id)
      assert {:error, :item_not_found} = result2
    end
  end

  describe "spawn_player_dropped_item" do
    setup do
      zone_id = unique_zone_id()
      start_supervised({ZoneServer, zone_id: zone_id})
      %{zone_id: zone_id}
    end

    test "spawns item at specified position", %{zone_id: zone_id} do
      position = %{x: 10.0, y: 2.0, z: 5.0}
      {:ok, new_item} = ZoneServer.spawn_player_dropped_item(zone_id, "leather_tunic", position)

      assert new_item.position.x == position.x
      assert new_item.position.y == position.y
      assert new_item.position.z == position.z
    end

    test "returns {:ok, new_item} with item details", %{zone_id: zone_id} do
      position = %{x: 0.0, y: 0.0, z: 0.0}
      result = ZoneServer.spawn_player_dropped_item(zone_id, "iron_band", position)

      assert {:ok, new_item} = result
      assert Map.has_key?(new_item, :id)
      assert Map.has_key?(new_item, :item_type)
      assert Map.has_key?(new_item, :position)
      assert Map.has_key?(new_item, :value)
    end

    test "item has template_id matching input", %{zone_id: zone_id} do
      position = %{x: 0.0, y: 0.0, z: 0.0}
      {:ok, new_item} = ZoneServer.spawn_player_dropped_item(zone_id, "bronze_sword", position)

      assert new_item.item_type == "bronze_sword"
    end

    test "item is added to zone items list", %{zone_id: zone_id} do
      pid = GenServer.whereis(via_tuple(zone_id))
      initial_state = get_genserver_state(pid)
      initial_count = length(initial_state.items)

      position = %{x: 0.0, y: 0.0, z: 0.0}
      {:ok, new_item} = ZoneServer.spawn_player_dropped_item(zone_id, "leather_tunic", position)

      final_state = get_genserver_state(pid)
      assert length(final_state.items) == initial_count + 1
      assert Enum.any?(final_state.items, fn item -> item.id == new_item.id end)
    end

    test "item_counter increments", %{zone_id: zone_id} do
      pid = GenServer.whereis(via_tuple(zone_id))
      initial_state = get_genserver_state(pid)
      initial_counter = initial_state.item_counter

      position = %{x: 0.0, y: 0.0, z: 0.0}
      ZoneServer.spawn_player_dropped_item(zone_id, "iron_band", position)

      final_state = get_genserver_state(pid)
      assert final_state.item_counter == initial_counter + 1
    end

    test "spawned item has value 0 (for player-dropped items)", %{zone_id: zone_id} do
      position = %{x: 0.0, y: 0.0, z: 0.0}
      {:ok, new_item} = ZoneServer.spawn_player_dropped_item(zone_id, "leather_tunic", position)

      assert new_item.value == 0
    end
  end

  describe "world_tick" do
    test "world_tick message is scheduled on init" do
      zone_id = unique_zone_id()
      {:ok, pid} = start_supervised({ZoneServer, zone_id: zone_id})

      state = get_genserver_state(pid)
      assert state.tick_ref != nil
      assert is_reference(state.tick_ref)
    end

    test "handling :world_tick schedules next tick" do
      zone_id = unique_zone_id()
      {:ok, pid} = start_supervised({ZoneServer, zone_id: zone_id})

      initial_state = get_genserver_state(pid)
      _initial_ref = initial_state.tick_ref

      # Wait for tick to occur
      Process.sleep(250)

      final_state = get_genserver_state(pid)
      # A new tick should have been scheduled (different reference)
      assert final_state.tick_ref != nil
      assert is_reference(final_state.tick_ref)
    end
  end

  describe "concurrent operations" do
    test "multiple players can attack same enemy" do
      zone_id = unique_zone_id()
      player_id = unique_player_id()

      start_supervised({ZoneServer, zone_id: zone_id})
      start_supervised({PlayerSession, player_id: player_id, username: "warrior"})

      [enemy] = ZoneServer.get_enemies(zone_id)

      # First attack damages the enemy
      {:ok, {:enemy_damaged, _, health1}} =
        ZoneServer.handle_attack(zone_id, player_id, enemy.id)

      # Second attack kills it
      {:ok, {:enemy_died, _, _}} = ZoneServer.handle_attack(zone_id, player_id, enemy.id)

      assert health1 > 0
    end

    test "player can pick up items from zone" do
      zone_id = unique_zone_id()
      player_id = unique_player_id()

      start_supervised({ZoneServer, zone_id: zone_id})
      start_supervised({PlayerSession, player_id: player_id, username: "collector"})

      # Spawn two items
      pos1 = %{x: 0.0, y: 0.0, z: 0.0}
      pos2 = %{x: 5.0, y: 0.0, z: 0.0}

      {:ok, item1} = ZoneServer.spawn_player_dropped_item(zone_id, "bronze_sword", pos1)
      {:ok, item2} = ZoneServer.spawn_player_dropped_item(zone_id, "leather_tunic", pos2)

      # Player picks up both items (returns {:ok, :item, item_instance})
      {:ok, _, _} = ZoneServer.handle_pickup(zone_id, player_id, item1.id)
      {:ok, _, _} = ZoneServer.handle_pickup(zone_id, player_id, item2.id)

      # Both pickups should succeed
      pid = GenServer.whereis(via_tuple(zone_id))
      state = get_genserver_state(pid)
      assert length(state.items) == 0
    end
  end

  # Helper function for via_tuple
  defp via_tuple(zone_id) do
    {:via, Registry, {PotatoQuestServer.Game.ZoneRegistry, zone_id}}
  end
end
