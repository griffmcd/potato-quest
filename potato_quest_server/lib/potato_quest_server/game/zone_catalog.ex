defmodule PotatoQuestServer.Game.ZoneCatalog do
  @moduledoc """
  Catalog of all zone types, their configurations, and spawn data.
  Used for creating zone instances and procedural generation.
  """

  @zone_templates %{
    # Safe Zones
    "town_square" => %{
      name: "Town Square",
      type: :town,
      zone_id: "town_square",
      permanent: true,              # Always exists, same layout
      seed_based: true,              # Uses world seed for consistency
      allow_pvp: false,
      enemy_spawns: [],              # Safe zone, no enemies
      size: %{width: 100, height: 100},
      spawn_points: [
        %{id: "main_gate", position: %{x: 0, y: 1, z: -45}},
        %{id: "fountain", position: %{x: 0, y: 1, z: 0}},
        %{id: "market", position: %{x: 20, y: 1, z: 10}}
      ]
    },

    "spawn_town" => %{
      name: "Starter Town",
      type: :town,
      zone_id: "spawn_town",
      permanent: true,
      seed_based: true,
      allow_pvp: false,
      enemy_spawns: [
        %{type: :bigfoot, count: 2, patrol_radius: 8.0}
      ],
      size: %{width: 60, height: 60},
      spawn_points: [
        %{id: "town_entrance", position: %{x: 0, y: 1, z: -20}}
      ]
    },

    # Wilderness Zones
    "forest_clearing" => %{
      name: "Whispering Woods",
      type: :wilderness,
      zone_id_prefix: "forest",      # Creates forest_001, forest_002, etc
      permanent: false,              # Instance-based
      seed_based: false,             # Random each time
      allow_pvp: true,
      enemy_spawns: [
        %{type: :pig_man, count: 3, patrol_radius: 10.0},
        %{type: :wolf, count: 2, patrol_radius: 15.0}  # Future enemy type
      ],
      size: %{width: 80, height: 80},
      difficulty: 1                  # For scaling enemy stats
    }
  }

  def get_template(zone_type), do: Map.get(@zone_templates, zone_type)
  def all_templates, do: @zone_templates
  def permanent_zones, do: Enum.filter(@zone_templates, fn {_k, v} -> v.permanent end)
end
