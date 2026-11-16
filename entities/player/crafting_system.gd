class_name CraftingSystem
extends Node
## On-the-fly crafting. Every recipe is a short channel on the player and
## makes a soft noise for its whole duration.

const CRAFT_NOISE_RADIUS: float = 3.0

## "consumes" is used up; "requires" must be carried but is kept.
const RECIPES: Array[Dictionary] = [
	{"id": &"tripwire", "label": "Bottle Tripwire", "result": ItemDB.TRIPWIRE, "time": 4.0,
		"consumes": {ItemDB.GLASS_BOTTLE: 1, ItemDB.LAN_CABLE: 1}, "requires": {}},
]

var _player: PlayerController = null
var _inventory: InventoryComponent = null


func setup(player: PlayerController, inventory: InventoryComponent) -> void:
	_player = player
	_inventory = inventory


func get_recipe(recipe_id: StringName) -> Dictionary:
	for recipe: Dictionary in RECIPES:
		if recipe["id"] == recipe_id:
			return recipe
	return {}


func can_craft(recipe: Dictionary) -> bool:
	return get_missing(recipe).is_empty()


## Names of the ingredients still needed for a recipe.
func get_missing(recipe: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	for group: String in ["consumes", "requires"]:
		var needs: Dictionary = recipe[group]
		for item_id: StringName in needs:
			var count: int = needs[item_id]
			if not _inventory.has_item(item_id, count):
				missing.append(ItemDB.get_item_name(item_id))
	return missing


## One line per recipe for the crafting panel.
func describe(recipe: Dictionary) -> String:
	var parts: Array[String] = []
	var consumes: Dictionary = recipe["consumes"]
	for item_id: StringName in consumes:
		parts.append(ItemDB.get_item_name(item_id))
	var requires: Dictionary = recipe["requires"]
	for item_id: StringName in requires:
		parts.append("%s (kept)" % ItemDB.get_item_name(item_id))
	return "%s  =  %s" % [recipe["label"], " + ".join(parts)]


## Starts crafting. Returns false if ingredients are missing or Juan is busy.
func craft(recipe_id: StringName) -> bool:
	var recipe: Dictionary = get_recipe(recipe_id)
	if recipe.is_empty() or _player == null:
		return false
	var missing: Array[String] = get_missing(recipe)
	if not missing.is_empty():
		EventBus.ui_notification.emit("Missing: %s" % ", ".join(missing), 2.2)
		return false
	var label: String = recipe["label"]
	var time: float = recipe["time"]
	return _player.start_channel("Making %s" % label, time, _finish.bind(recipe_id), {
		"noise_type": &"craft_soft", "noise_radius": CRAFT_NOISE_RADIUS, "noise_interval": 1.0,
	})


func _finish(recipe_id: StringName) -> void:
	var recipe: Dictionary = get_recipe(recipe_id)
	if recipe.is_empty() or not can_craft(recipe):
		return
	var consumes: Dictionary = recipe["consumes"]
	for item_id: StringName in consumes:
		var count: int = consumes[item_id]
		_inventory.remove_item(item_id, count)
	var result: StringName = recipe["result"]
	if _inventory.add_item(result, 1) > 0:
		_player.drop_item_in_world(result, 1)
	EventBus.item_crafted.emit(result)
	EventBus.ui_notification.emit("Made %s" % ItemDB.get_item_name(result), 2.0)
