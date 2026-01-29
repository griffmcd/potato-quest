defmodule PotatoQuestServer.Game.ProcGen do
  @moduledoc """
  Procedural generation utilities for creating dynamic zones.
  Supports both seed-based (deterministic) and random generation.
  """

  @doc """
  Generate zone layout based on template and seed.
  For permanent zones, use world seed.
  For instance zones, use random seed.
  """
  def generate_zone(template, seed) do
    # Seed the random number generator
    :rand.seed(:exsplus, {seed, seed * 2, seed * 3})

    %{
      zone_id: generate_zone_id(template, seed),
      layout: generate_layout(template),
      enemy_spawns: generate_enemy_spawns(template),
      resource_nodes: generate_resource_nodes(template),
      loot_caches: generate_loot_caches(template)
    }
  end

  defp generate_zone_id(%{permanent: true, zone_id: id}, _seed), do: id
  defp generate_zone_id(%{zone_id_prefix: prefix}, seed) do
    "#{prefix}_#{:erlang.phash2(seed, 10000)}"
  end

  defp generate_layout(template) do
    # TODO: Implement layout generation
    # For now, just use template size
    %{
      width: template.size.width,
      height: template.size.height,
      obstacles: []  # Future: Generate walls, rocks, etc
    }
  end

  defp generate_enemy_spawns(template) do
    Enum.map(template.enemy_spawns || [], fn spawn_config ->
      for _i <- 1..spawn_config.count do
        random_position(template.size)
      end
    end)
    |> List.flatten()
  end

  defp generate_resource_nodes(_template) do
    # Future: Trees, rocks, ore veins
    []
  end

  defp generate_loot_caches(_template) do
    # Future: Hidden treasure chests
    []
  end

  defp random_position(size) do
    %{
      x: :rand.uniform(trunc(size.width)) - trunc(size.width / 2),
      y: 1.0,
      z: :rand.uniform(trunc(size.height)) - trunc(size.height / 2)
    }
  end
end
