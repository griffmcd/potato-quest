defmodule PotatoQuestServer.Game.ItemCatalogTest do
  use ExUnit.Case, async: true

  alias PotatoQuestServer.Game.ItemCatalog

  describe "all_items/0" do
    test "returns a list of all items" do
      items = ItemCatalog.all_items()
      assert is_list(items)
    end

    test "returns at least one item" do
      items = ItemCatalog.all_items()
      assert length(items) > 0
    end

    test "all items have required fields" do
      items = ItemCatalog.all_items()

      Enum.each(items, fn item ->
        assert Map.has_key?(item, :id)
        assert Map.has_key?(item, :name)
        assert Map.has_key?(item, :type)
        assert Map.has_key?(item, :slot)
        assert Map.has_key?(item, :rarity)
        assert Map.has_key?(item, :stats)
        assert Map.has_key?(item, :weight)
        assert Map.has_key?(item, :value)
        assert Map.has_key?(item, :stackable)

        # Verify stats structure
        assert Map.has_key?(item.stats, :damage)
        assert Map.has_key?(item.stats, :str_bonus)
        assert Map.has_key?(item.stats, :def_bonus)
        assert Map.has_key?(item.stats, :dex_bonus)
        assert Map.has_key?(item.stats, :int_bonus)
      end)
    end
  end

  describe "get_item/1" do
    test "returns bronze_sword when given 'bronze_sword' id" do
      item = ItemCatalog.get_item("bronze_sword")
      assert item != nil
      assert item.id == "bronze_sword"
      assert item.name == "Bronze Sword"
    end

    test "returns wooden_shield when given 'wooden_shield' id" do
      item = ItemCatalog.get_item("wooden_shield")
      assert item != nil
      assert item.id == "wooden_shield"
      assert item.name == "Wooden Shield"
    end

    test "returns leather_tunic when given 'leather_tunic' id" do
      item = ItemCatalog.get_item("leather_tunic")
      assert item != nil
      assert item.id == "leather_tunic"
      assert item.name == "Leather Tunic"
    end

    test "returns iron_band when given 'iron_band' id" do
      item = ItemCatalog.get_item("iron_band")
      assert item != nil
      assert item.id == "iron_band"
      assert item.name == "Iron Band"
    end

    test "returns nil for non-existent item id" do
      item = ItemCatalog.get_item("non_existent_item")
      assert item == nil
    end
  end

  describe "item structure validation" do
    test "bronze_sword has correct stats" do
      item = ItemCatalog.get_item("bronze_sword")
      assert item.stats.damage == 15
      assert item.stats.str_bonus == 5
    end

    test "all equipment items have stackable: false" do
      items = ItemCatalog.all_items()
      equipment_items = Enum.filter(items, fn item -> item.type == :equipment end)

      Enum.each(equipment_items, fn item ->
        assert item.stackable == false
      end)
    end

    test "all items have valid rarity values" do
      items = ItemCatalog.all_items()
      valid_rarities = [:common, :uncommon, :rare, :epic, :legendary]

      Enum.each(items, fn item ->
        assert item.rarity in valid_rarities,
               "Item #{item.id} has invalid rarity: #{item.rarity}"
      end)
    end
  end
end
