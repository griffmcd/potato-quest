defmodule PotatoQuestServer.Game.EnemyCatalog do
  @moduledoc """
  Catalog of all enemy types, their stats, and AI behavior configs.
  """

  @type enemy_id :: String.t()
  @type enemy :: %{
    enemy_id: enemy_id(),
    type: :pig_man | :wolf | :bigfoot | :none,
    position: %{
      x: float(),
      y: float(),
      z: float()
    },
    health: integer(),
    max_health: integer(),
    state: :alive | :dead | :idle | :chasing | :attacking | :returning | :unknown
  }

  @enemies %{
    pig_man: %{
      name: "Pig Man",
      max_health: 50,
      damage: 8,
      defense: 2,
      aggro_range: 10.0,           # Distance to detect players
      attack_range: 2.0,           # Distance to melee attack
      chase_speed: 3.0,            # Units per second when chasing
      patrol_speed: 1.5,           # Units per second when wandering
      loot_table: :pig_man,
      xp_reward: 25
    },

    wolf: %{
      name: "Wild Wolf",
      max_health: 35,
      damage: 12,
      defense: 1,
      aggro_range: 15.0,           # Wolves detect from farther
      attack_range: 2.5,
      chase_speed: 5.0,            # Wolves are faster
      patrol_speed: 2.0,
      loot_table: :wolf,
      xp_reward: 30
    },

    bigfoot: %{
      name: "Bigfoot",
      max_health: 80,
      damage: 12,
      defense: 4,
      aggro_range: 12.0,
      attack_range: 2.5,
      chase_speed: 2.5,
      patrol_speed: 1.0,
      attack_cooldown: 2.5,        # NEW FIELD
      respawn_time: 45.0,          # NEW FIELD
      loot_table: :bigfoot,
      xp_reward: 50
    }
  }

  def get(type), do: Map.get(@enemies, type)
  def all, do: @enemies
end
