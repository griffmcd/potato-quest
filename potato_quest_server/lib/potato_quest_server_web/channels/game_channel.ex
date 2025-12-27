defmodule PotatoQuestServerWeb.GameChannel do
  use Phoenix.Channel

  require Logger

  alias PotatoQuestServerWeb.Presence

  @impl true
  def join("game:lobby", %{"username" => username}, socket) do
    Logger.info("Player joining: #{username}")

    # Assign username to socket
    socket = assign(socket, :username, username)
    player_id = generate_player_id()
    socket = assign(socket, :player_id, player_id)
    # start player genserver
    {:ok, _pid} = DynamicSupervisor.start_child(
      PotatoQuestServer.Game.PlayerSupervisor,
      {PotatoQuestServer.Game.PlayerSession, player_id: player_id, username: username}
    )
    # get current player count so that we can spawn the player in empty space
    # we will calculate spawn position in a circle
    player_count = map_size(Presence.list(socket))
    spawn_radius = 3.0
    angle = player_count * (2 * :math.pi() / 8) # 8 max positions--adjust if needed
    spawn_x = spawn_radius * :math.cos(angle)
    spawn_z = spawn_radius * :math.sin(angle)
    socket = assign(socket, :position, %{x: spawn_x, y: 1.0, z: spawn_z})

    # Get list of current players in lobby
    send(self(), :after_join)

    {:ok, %{player_id: socket.assigns.player_id}, socket}
  end

  def join("game:lobby", _params, _socket) do
    {:error, %{reason: "username required"}}
  end

  @impl true
  def handle_info(:after_join, socket) do
    # Track this player with Presence
    {:ok, _} = Presence.track(socket, socket.assigns.player_id, %{
      username: socket.assigns.username,
      position: socket.assigns.position,
      online_at: inspect(System.system_time(:second))
    })

    # Send lobby state to the new player
    players = get_lobby_players(socket)
    push(socket, "lobby:state", %{players: players})

    # Broadcast that a new player joined
    broadcast!(socket, "player:joined", %{
      player_id: socket.assigns.player_id,
      username: socket.assigns.username,
      position: socket.assigns.position
    })

    {:noreply, socket}
  end

  @impl true
  def handle_in("player:move", %{
    "x" => x,
    "y" => y,
    "z" => z,
    "pitch" => pitch,
    "yaw" => yaw,
    "rotation_y" => rotation_y
  }, socket) do
    # Update position in socket state
    new_position = %{x: x, y: y, z: z}
    new_rotation = %{pitch: pitch, yaw: yaw, rotation_y: rotation_y}
    socket = socket
      |> assign(:position, new_position)
      |> assign(:rotation, new_rotation)

    # Update position in Presence
    Presence.update(socket, socket.assigns.player_id, %{
      username: socket.assigns.username,
      position: new_position,
      rotation: new_rotation,
      online_at: inspect(System.system_time(:second))
    })


    # Broadcast movement to all other players
    broadcast!(socket, "player:moved", %{
      player_id: socket.assigns.player_id,
      position: new_position,
      rotation: new_rotation
    })

    {:noreply, socket}
  end

  @impl true
  def handle_in("chat:message", %{"message" => message}, socket) do
    # Broadcast chat message to all players
    broadcast!(socket, "chat:message", %{
      player_id: socket.assigns.player_id,
      username: socket.assigns.username,
      message: message
    })

    {:noreply, socket}
  end

  @impl true
  def handle_in("lobby:request_state", _payload, socket) do
    # Get current players from Presence
    players = get_lobby_players(socket)

    # Send lobby state directly to this player
    push(socket, "lobby:state", %{players: players})

    {:noreply, socket}
  end

  @impl true
  def handle_in("zone:request_state", _payload, socket) do
    zone_id = "spawn_town"
    enemies = PotatoQuestServer.Game.ZoneServer.get_enemies(zone_id)
    push(socket, "zone:state", %{enemies: enemies})
    {:noreply, socket}
  end

  @impl true
  def handle_in("player:attack", %{"enemy_id" => enemy_id}, socket) do
    player_id = socket.assigns.player_id
    zone_id = "spawn_town"  # TODO: should not be hardcoded. Later phase work

    case PotatoQuestServer.Game.ZoneServer.handle_attack(zone_id, player_id, enemy_id) do
      {:ok, {:enemy_damaged, damage, new_health}} ->
        broadcast!(socket, "enemy:damaged", %{
          enemy_id: enemy_id,
          damage: damage,
          health: new_health,
          attacker_id: player_id
        })
        {:noreply, socket}
      {:ok, {:enemy_died, damage, spawned_items}} ->
        broadcast!(socket, "enemy:damaged", %{
          enemy_id: enemy_id,
          damage: damage,
          health: 0,
          attacker_id: player_id
        })
        broadcast!(socket, "enemy:died", %{
          enemy_id: enemy_id,
          spawned_items: spawned_items
        })
        {:noreply, socket}
      {:error, reason} ->
        push(socket, "error", %{reason: to_string(reason)})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_in("player:pickup_item", %{"item_id" => item_id}, socket) do
    player_id = socket.assigns.player_id
    zone_id = "spawn_town"

    case PotatoQuestServer.Game.ZoneServer.handle_pickup(zone_id, player_id, item_id) do
      {:ok, :gold, _amount} ->
        player_state = PotatoQuestServer.Game.PlayerSession.get_state(player_id)

        push(socket, "inventory:updated", %{
          gold: player_state.gold
        })

        broadcast!(socket, "item:picked_up", %{
          player_id: player_id,
          item_id: item_id
        })

        {:noreply, socket}

      {:ok, :item, _item_instance} ->
        player_state = PotatoQuestServer.Game.PlayerSession.get_state(player_id)

        push(socket, "inventory:updated", %{
          inventory: player_state.inventory,
          gold: player_state.gold
        })

        broadcast!(socket, "item:picked_up", %{
          player_id: player_id,
          item_id: item_id
        })

        {:noreply, socket}

      {:error, reason} ->
        push(socket, "error", %{reason: to_string(reason)})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_in("player:equip_item", %{"instance_id" => instance_id}, socket) do
    player_id = socket.assigns.player_id

    case PotatoQuestServer.Game.PlayerSession.equip_item(player_id, instance_id) do
      {:ok, equipment, stats} ->
        player_state = PotatoQuestServer.Game.PlayerSession.get_state(player_id)

        push(socket, "equipment:updated", %{
          equipment: equipment,
          inventory: player_state.inventory,
          stats: stats
        })

        {:noreply, socket}

      {:error, reason} ->
        push(socket, "error", %{message: "Failed to equip: #{reason}"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_in("player:unequip_item", %{"slot" => slot_name}, socket) do
    player_id = socket.assigns.player_id
    slot = String.to_existing_atom(slot_name)

    case PotatoQuestServer.Game.PlayerSession.unequip_item(player_id, slot) do
      {:ok, equipment, stats} ->
        player_state = PotatoQuestServer.Game.PlayerSession.get_state(player_id)

        push(socket, "equipment:updated", %{
          equipment: equipment,
          inventory: player_state.inventory,
          stats: stats
        })

        {:noreply, socket}

      {:error, reason} ->
        push(socket, "error", %{message: "Failed to unequip: #{reason}"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_in("player:drop_item", %{"instance_id" => instance_id}, socket) do
    player_id = socket.assigns.player_id

    case PotatoQuestServer.Game.PlayerSession.drop_item(player_id, instance_id) do
      {:ok, _dropped_item} ->
        player_state = PotatoQuestServer.Game.PlayerSession.get_state(player_id)

        push(socket, "inventory:updated", %{
          inventory: player_state.inventory,
          gold: player_state.gold
        })

        {:noreply, socket}

      {:error, reason} ->
        push(socket, "error", %{message: "Failed to drop: #{reason}"})
        {:noreply, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    # Broadcast that player left
    broadcast!(socket, "player:left", %{
      player_id: socket.assigns.player_id,
      username: socket.assigns.username
    })

    :ok
  end

  # Private functions

  defp generate_player_id do
    # For now, use a simple UUID
    # Later we'll use proper database IDs
    "player_#{System.unique_integer([:positive])}"
  end

  defp get_lobby_players(socket) do
    # Get all players from Presence
    presence_list = Presence.list(socket)

    # Convert Presence data to player list format
    Enum.map(presence_list, fn {player_id, %{metas: [meta | _]}} ->
      %{
        player_id: player_id,
        username: meta.username,
        position: meta.position
      }
    end)
  end
end
