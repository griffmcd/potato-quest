defmodule PotatoQuestServer.Game.EnemyCatalog do
  @type enemy_id :: String.t()
  @type enemy :: %{
    enemy_id: enemy_id(),
    type: :pig_man | :none,
    position: %{
      x: float(),
      y: float(),
      z: float()
    },
    health: integer(),
    max_health: integer(),
    state: :alive | :dead | :unknown
  }

end
