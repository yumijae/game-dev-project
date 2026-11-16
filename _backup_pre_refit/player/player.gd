class_name Player
extends JudeController
## Extended Player controller for Jude Villanueva.
## Inherits full survival physics from JudeController while maintaining compatibility
## with legacy HUD hooks and existing map scenes.

signal inventory_changed(items: Array, total_value: int)
signal prompt_changed(text: String)

var inventory: Array = []
var total_value: int = 0


func _ready() -> void:
	super._ready()
	# Bridge prompt signal to legacy prompt_changed for HUD
	interaction_prompt_changed.connect(func(t: String) -> void:
		prompt_changed.emit(t)
	)


func add_loot(item_name: String, value: int, rarity: String) -> void:
	inventory.append({"name": item_name, "value": value, "rarity": rarity})
	total_value += value
	inventory_changed.emit(inventory, total_value)
