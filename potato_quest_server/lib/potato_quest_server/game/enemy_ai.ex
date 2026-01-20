defmodule PotatoQuestServer.Game.EnemyAI do
  @moduledoc """
  Enemy AI behavior system. Handles aggro detection, pathfinding,
  and combat decision-making.
  """

  alias PotatoQuestServer.Game.Pathfinder
  alias PotatoQuestServer.Game.EnemyCatalog

  @doc """
  Update all enemies in a zone. Called from zone world tick.
  Returns updated enemy list and list of broadcasts to send.
  """
  def update_all(enemies, players, delta_time) do
    Enum.map(enemies, fn enemy ->
      case enemy.state do
        :dead ->
          enemy  # Don't update dead enemies

        _ ->
          update_enemy(enemy, players, delta_time)
      end
    end)
  end

  defp update_enemy(enemy, players, delta_time) do
    catalog = EnemyCatalog.get(enemy.type)

    # 1. Check for nearby players
    nearest_player = find_nearest_player(enemy, players, catalog.aggro_range)

    # 2. Decide action based on state
    enemy
    |> decide_action(nearest_player, catalog)
    |> execute_action(players, delta_time, catalog)
  end

  # State transitions
  defp decide_action(enemy, nil, _catalog) do
    # No players nearby - return to patrol origin or wander
    %{enemy | state: :returning, target_player_id: nil}
  end

  defp decide_action(enemy, player, catalog) do
    distance = calculate_distance(enemy.position, player.position)

    cond do
      distance <= catalog.attack_range ->
        %{enemy | state: :attacking, target_player_id: player.id}

      distance <= catalog.aggro_range ->
        %{enemy | state: :chasing, target_player_id: player.id}

      true ->
        %{enemy | state: :idle, target_player_id: nil}
    end
  end

  # Action execution
  defp execute_action(%{state: :idle} = enemy, _players, delta_time, catalog) do
    # Small random wander near patrol origin
    wander_slightly(enemy, delta_time, catalog.patrol_speed)
  end

  defp execute_action(%{state: :chasing} = enemy, players, delta_time, catalog) do
    target = Enum.find(players, fn {id, _} -> id == enemy.target_player_id end)

    case target do
      {_id, player} ->
        # Use A* to find path to player
        path = Pathfinder.find_path(enemy.position, player.position)

        # Move along path
        move_along_path(enemy, path, delta_time, catalog.chase_speed)

      nil ->
        %{enemy | state: :idle, target_player_id: nil}
    end
  end

  defp execute_action(%{state: :attacking} = enemy, _players, _delta_time, _catalog) do
    # Combat handled separately by zone server
    # Just keep enemy in attack state (they don't move while attacking)
    enemy
  end

  defp execute_action(%{state: :returning} = enemy, _players, delta_time, catalog) do
    # Return to patrol origin
    path = Pathfinder.find_path(enemy.position, enemy.patrol_origin)

    enemy = move_along_path(enemy, path, delta_time, catalog.patrol_speed)

    # If close to origin, switch to idle
    if calculate_distance(enemy.position, enemy.patrol_origin) < 1.0 do
      %{enemy | state: :idle}
    else
      enemy
    end
  end

  # Helper functions
  defp find_nearest_player(enemy, players, aggro_range) do
    players
    |> Enum.map(fn {id, player} ->
      {id, player, calculate_distance(enemy.position, player.position)}
    end)
    |> Enum.filter(fn {_id, _player, dist} -> dist <= aggro_range end)
    |> Enum.min_by(fn {_id, _player, dist} -> dist end, fn -> nil end)
    |> case do
      {id, player, _dist} -> %{id: id, position: player.position}
      nil -> nil
    end
  end

  defp calculate_distance(pos1, pos2) do
    dx = pos1.x - pos2.x
    dz = pos1.z - pos2.z
    :math.sqrt(dx * dx + dz * dz)
  end

  defp move_along_path(enemy, [], _delta, _speed), do: enemy

  defp move_along_path(enemy, [next_point | rest], delta_time, speed) do
    direction = normalize_vector(%{
      x: next_point.x - enemy.position.x,
      z: next_point.z - enemy.position.z
    })

    movement_distance = speed * delta_time

    new_position = %{
      x: enemy.position.x + direction.x * movement_distance,
      y: enemy.position.y,
      z: enemy.position.z + direction.z * movement_distance
    }

    %{enemy | position: new_position, path: rest}
  end

  defp wander_slightly(enemy, delta_time, speed) do
    # Small random movement near patrol origin
    max_wander = 5.0

    offset = %{
      x: (:rand.uniform() - 0.5) * 2 * max_wander,
      z: (:rand.uniform() - 0.5) * 2 * max_wander
    }

    target = %{
      x: enemy.patrol_origin.x + offset.x,
      y: enemy.patrol_origin.y,
      z: enemy.patrol_origin.z + offset.z
    }

    direction = normalize_vector(%{
      x: target.x - enemy.position.x,
      z: target.z - enemy.position.z
    })

    new_position = %{
      x: enemy.position.x + direction.x * speed * delta_time,
      y: enemy.position.y,
      z: enemy.position.z + direction.z * speed * delta_time
    }

    %{enemy | position: new_position}
  end

  defp normalize_vector(%{x: x, z: z}) do
    magnitude = :math.sqrt(x * x + z * z)

    if magnitude > 0 do
      %{x: x / magnitude, z: z / magnitude}
    else
      %{x: 0, z: 0}
    end
  end
end
