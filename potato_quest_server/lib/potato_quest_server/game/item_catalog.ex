defmodule PotatoQuestServer.Game.ItemCatalog do
  @type item_id :: integer()
  @type item :: %{
    id: item_id(),
    name: String.t(),
    type: :equipment | :material | :consumable,
    slot: :weapon | :head | :chest | :legs | :shield | :ring | :amulet,
    rarity: :common | :uncommon | :rare | :epic | :legendary,
    stats: %{
      damage: integer(),
      str_bonus: integer(),
      def_bonus: integer(),
      dex_bonus: integer(),
      int_bonus: integer()
    },
    weight: integer(),
    value: integer(),
    stackable: boolean()
  }

  def all_items do
    @items
  end

  def get_item(item_id) do
    Enum.find(@items, fn item -> item.id == item_id end)
  end

  @items [
    %{id: "bronze_sword",
      name: "Bronze Sword",
      type: :equipment,
      slot: :weapon,
      rarity: :common,
      stats: %{
        damage: 15,
        str_bonus: 5,
        def_bonus: 0,
        dex_bonus: 0,
        int_bonus: 0
      },
      weight: 5,
      value: 25,
      stackable: false
    },
    %{id: "wooden_shield",
      name: "Wooden Shield",
      type: :equipment,
      slot: :shield,
      rarity: :common,
      stats: %{
        damage: 0,
        str_bonus: 0,
        def_bonus: 3,
        dex_bonus: 0,
        int_bonus: 0
      },
      weight: 3,
      value: 15,
      stackable: false
    },
    %{id: "leather_tunic",
      name: "Leather Tunic",
      type: :equipment,
      slot: :chest,
      rarity: :common,
      stats: %{
        damage: 0,
        str_bonus: 0,
        def_bonus: 2,
        dex_bonus: 0,
        int_bonus: 0
      },
      weight: 2,
      value: 20,
      stackable: false
    },
    %{id: "iron_band",
      name: "Iron Band",
      type: :equipment,
      slot: :ring,
      rarity: :common,
      stats: %{
        damage: 0,
        str_bonus: 2,
        def_bonus: 0,
        dex_bonus: 0,
        int_bonus: 0
      },
      weight: 1,
      value: 30,
      stackable: false
    }
  ]

end
