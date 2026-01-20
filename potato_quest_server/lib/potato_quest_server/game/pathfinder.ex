defmodule PotatoQuestServer.Game.Pathfinder do
  @moduledoc """
  A* pathfinding implementation for enemy navigation.
  Uses a grid-based approach with obstacle detection.
  """

  @grid_size 1.0  # 1 unit per grid cell

  @doc """
  Find path from start to goal using A* algorithm.
  Returns list of waypoints to follow.
  """
  def find_path(start_pos, goal_pos, obstacles \\ []) do
    start_node = to_grid(start_pos)
    goal_node = to_grid(goal_pos)

    # Simple A* implementation
    open_set = MapSet.new([start_node])
    closed_set = MapSet.new()

    # g_score: cost from start to node
    g_score = %{start_node => 0}

    # f_score: g_score + heuristic
    f_score = %{start_node => heuristic(start_node, goal_node)}

    # came_from: for path reconstruction
    came_from = %{}

    path = a_star_loop(
      open_set,
      closed_set,
      g_score,
      f_score,
      came_from,
      goal_node,
      obstacles
    )

    # Convert grid path back to world positions
    Enum.map(path, &from_grid/1)
  end

  defp a_star_loop(open_set, closed_set, g_score, f_score, came_from, goal, obstacles) do
    if MapSet.size(open_set) == 0 do
      []  # No path found
    else
      # Get node with lowest f_score
      current = Enum.min_by(open_set, fn node -> Map.get(f_score, node, :infinity) end)

      if current == goal do
        # Reconstruct path
        reconstruct_path(came_from, current)
      else
        open_set = MapSet.delete(open_set, current)
        closed_set = MapSet.put(closed_set, current)

        # Check neighbors
        neighbors = get_neighbors(current)
        |> Enum.reject(fn n -> MapSet.member?(closed_set, n) end)
        |> Enum.reject(fn n -> is_obstacle?(n, obstacles) end)

        {new_open, new_g, new_f, new_came_from} =
          Enum.reduce(neighbors, {open_set, g_score, f_score, came_from}, fn neighbor, acc ->
            {o, g, f, cf} = acc

            tentative_g = Map.get(g, current) + 1  # Distance between grid cells is 1

            if tentative_g < Map.get(g, neighbor, :infinity) do
              # This path is better
              {
                MapSet.put(o, neighbor),
                Map.put(g, neighbor, tentative_g),
                Map.put(f, neighbor, tentative_g + heuristic(neighbor, goal)),
                Map.put(cf, neighbor, current)
              }
            else
              acc
            end
          end)

        a_star_loop(new_open, closed_set, new_g, new_f, new_came_from, goal, obstacles)
      end
    end
  end

  defp reconstruct_path(came_from, current, path \\ []) do
    path = [current | path]

    case Map.get(came_from, current) do
      nil -> path
      parent -> reconstruct_path(came_from, parent, path)
    end
  end

  defp get_neighbors({x, z}) do
    [
      {x + 1, z},      # East
      {x - 1, z},      # West
      {x, z + 1},      # North
      {x, z - 1},      # South
      {x + 1, z + 1},  # NE (diagonal)
      {x - 1, z + 1},  # NW
      {x + 1, z - 1},  # SE
      {x - 1, z - 1}   # SW
    ]
  end

  defp heuristic({x1, z1}, {x2, z2}) do
    # Manhattan distance
    abs(x1 - x2) + abs(z1 - z2)
  end

  defp is_obstacle?(_node, []), do: false
  defp is_obstacle?(node, obstacles) do
    Enum.any?(obstacles, fn obs -> obs == node end)
  end

  defp to_grid(%{x: x, z: z}) do
    {round(x / @grid_size), round(z / @grid_size)}
  end

  defp from_grid({x, z}) do
    %{x: x * @grid_size, y: 0.0, z: z * @grid_size}
  end
end
