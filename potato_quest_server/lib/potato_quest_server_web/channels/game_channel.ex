defmodule PotatoQuestServerWeb.GameChannel do
  use Phoenix.Channel

  require Logger

  alias PotatoQuestServerWeb.Presence

  @impl true
  def join("game:lobby", %{"username" => username}, socket) do
    Logger.info("Player joining: #{username}")

    # Assign username to socket
    socket = assign(socket, :username, username)
    socket = assign(socket, :player_id, generate_player_id())
    socket = assign(socket, :position, %{x: 0, y: 0, z: 0})

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

    # Broadcast that a new player joined
    broadcast!(socket, "player:joined", %{
      player_id: socket.assigns.player_id,
      username: socket.assigns.username,
      position: socket.assigns.position
    })

    {:noreply, socket}
  end

  @impl true
  def handle_in("player:move", %{"x" => x, "y" => y, "z" => z}, socket) do
    # Update position in socket state
    new_position = %{x: x, y: y, z: z}
    socket = assign(socket, :position, new_position)

    # Update position in Presence
    Presence.update(socket, socket.assigns.player_id, %{
      username: socket.assigns.username,
      position: new_position,
      online_at: inspect(System.system_time(:second))
    })

    # Broadcast movement to all other players
    broadcast!(socket, "player:moved", %{
      player_id: socket.assigns.player_id,
      position: new_position
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
