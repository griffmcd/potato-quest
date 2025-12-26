defmodule PotatoQuestServerWeb.GameChannelTest do
  use PotatoQuestServerWeb.ChannelCase

  alias PotatoQuestServerWeb.UserSocket

  setup do
    {:ok, _, socket} =
      UserSocket
      |> socket("user_id", %{})
      |> subscribe_and_join(PotatoQuestServerWeb.GameChannel, "game:lobby", %{
        "username" => "test_player"
      })

    %{socket: socket}
  end

  test "join assigns username and player_id", %{socket: socket} do
    assert socket.assigns.username == "test_player"
    assert socket.assigns.player_id != nil
  end

  test "join broadcasts player:joined event", %{socket: _socket} do
    assert_broadcast "player:joined", %{
      player_id: _,
      username: "test_player",
      position: %{x: _, y: _, z: _}
    }
  end

  test "join sends lobby:state to new player", %{socket: _socket} do
    assert_push "lobby:state", %{players: _}
  end

  test "player:move broadcasts to other players", %{socket: socket} do
    push(socket, "player:move", %{
      "x" => 10,
      "y" => 0,
      "z" => 5,
      "pitch" => 0,
      "yaw" => 0,
      "rotation_y" => 0
    })

    assert_broadcast "player:moved", %{
      player_id: _,
      position: %{x: 10, y: 0, z: 5},
      rotation: %{pitch: 0, yaw: 0, rotation_y: 0}
    }
  end

  test "chat:message broadcasts to all players", %{socket: socket} do
    push(socket, "chat:message", %{"message" => "Hello world!"})

    assert_broadcast "chat:message", %{
      player_id: _,
      username: "test_player",
      message: "Hello world!"
    }
  end

  test "joining without username returns error" do
    assert {:error, %{reason: "username required"}} =
             UserSocket
             |> socket("user_id", %{})
             |> subscribe_and_join(PotatoQuestServerWeb.GameChannel, "game:lobby", %{})
  end
end
