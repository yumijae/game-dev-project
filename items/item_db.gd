class_name ItemDB
extends RefCounted
## Every carryable item in Expo Night. Pure data: ids, display names,
## stack sizes and the tint/size of the placeholder pickup mesh.

const GLASS_BOTTLE: StringName = &"glass_bottle"
const FIRE_EXTINGUISHER: StringName = &"fire_extinguisher"
const TASER: StringName = &"taser"
const TABLECLOTH_RAG: StringName = &"tablecloth_rag"
const GAUZE: StringName = &"gauze"
const ALCOHOL: StringName = &"rubbing_alcohol"
const WATER: StringName = &"bottled_water"
const REHAS_KEY: StringName = &"master_rehas_key"
const BOLT_CUTTERS: StringName = &"bolt_cutters"
const CROWBAR: StringName = &"crowbar"
const POWERBANK: StringName = &"powerbank"


## "use" is the label of the item's own action (left click with it in hand).
## A fire extinguisher's count is the number of bursts left in it.
## "kg" is the weight of one (of one burst, for the extinguisher): Juan can
## carry InventoryComponent.MAX_LOAD in all.
const ITEMS: Dictionary = {
	GLASS_BOTTLE: {"name": "Glass Bottle", "kg": 0.4, "stack": 3, "color": Color(0.6, 0.8, 0.75), "size": Vector3(0.07, 0.22, 0.07),
		"use": "Throw", "desc": "Empty. Throw it and it smashes loudly where it lands - every robot that hears it goes to look."},
	FIRE_EXTINGUISHER: {"name": "Fire Extinguisher", "kg": 1.5, "stack": 3, "color": Color(0.78, 0.08, 0.06), "size": Vector3(0.14, 0.42, 0.14),
		"use": "Spray (one burst)", "desc": "CO2. A burst in a robot's face whites out its sensors: it stops dead for a few seconds and loses you. The number is bursts left."},
	TASER: {"name": "Taser", "kg": 0.4, "stack": 3, "color": Color(0.95, 0.78, 0.1), "size": Vector3(0.16, 0.04, 0.06),
		"use": "Zap (single use)", "desc": "Campus security's cheap stun gun - good for one shot. Zap a robot within arm's reach and it locks up for a few seconds. POSE drops completely and stays down - until CONCIERGE comes to reboot it."},
	TABLECLOTH_RAG: {"name": "Tablecloth Rag", "kg": 0.2, "stack": 2, "color": Color(0.9, 0.9, 0.95), "size": Vector3(0.2, 0.03, 0.2),
		"use": "Disinfect & bandage (7 s)", "desc": "Torn dining linen. Works as a bandage."},
	GAUZE: {"name": "Gauze Roll", "kg": 0.05, "stack": 2, "color": Color(0.96, 0.96, 0.92), "size": Vector3(0.08, 0.06, 0.08),
		"use": "Disinfect & bandage (7 s)", "desc": "From the clinic kit. Needs rubbing alcohol."},
	ALCOHOL: {"name": "Rubbing Alcohol", "kg": 0.3, "stack": 2, "color": Color(0.35, 0.6, 0.9), "size": Vector3(0.07, 0.18, 0.05),
		"use": "Disinfect & bandage (7 s)", "desc": "70% isopropyl. Needs gauze or a tablecloth rag."},
	WATER: {"name": "Bottled Water", "kg": 0.5, "stack": 2, "color": Color(0.5, 0.75, 0.95), "size": Vector3(0.07, 0.2, 0.07),
		"use": "Drink (-35 Panic)", "desc": "Cold water. Steadies the breathing."},
	REHAS_KEY: {"name": "Master Gate Key", "kg": 0.05, "stack": 1, "color": Color(0.85, 0.7, 0.2), "size": Vector3(0.08, 0.015, 0.03),
		"desc": "Opens the padlock on the Main Lobby roll-up gate."},
	BOLT_CUTTERS: {"name": "Bolt Cutters", "kg": 2.5, "stack": 1, "color": Color(0.7, 0.15, 0.12), "size": Vector3(0.5, 0.05, 0.14),
		"desc": "From the MIT Office. Cuts the gate's chain."},
	CROWBAR: {"name": "Crowbar", "kg": 1.8, "stack": 1, "color": Color(0.2, 0.25, 0.5), "size": Vector3(0.6, 0.04, 0.08),
		"use": "Barricade a shut door (aim at it)", "desc": "From the Staff Room. Jam it under a shut door and nothing opens it from outside - SCUTTLE can't squeeze under it either. Only PROTOTYPE can batter it loose."},
	POWERBANK: {"name": "Powerbank", "kg": 0.25, "stack": 1, "color": Color(0.15, 0.15, 0.17), "size": Vector3(0.07, 0.02, 0.14),
		"use": "Charge phone (+30%)", "desc": "Someone's half-charged powerbank."},
}


static func has(item_id: StringName) -> bool:
	return ITEMS.has(item_id)


static func get_def(item_id: StringName) -> Dictionary:
	var definition: Dictionary = ITEMS.get(item_id, {})
	return definition


static func get_item_name(item_id: StringName) -> String:
	var definition: Dictionary = get_def(item_id)
	return definition.get("name", String(item_id))


static func get_description(item_id: StringName) -> String:
	var definition: Dictionary = get_def(item_id)
	return definition.get("desc", "")


static func get_max_stack(item_id: StringName) -> int:
	var definition: Dictionary = get_def(item_id)
	return definition.get("stack", 1)


## Weight of one of `item_id` in kilograms.
static func get_weight(item_id: StringName) -> float:
	var definition: Dictionary = get_def(item_id)
	return definition.get("kg", 0.0)


static func is_hands_only(item_id: StringName) -> bool:
	var definition: Dictionary = get_def(item_id)
	return definition.get("hands_only", false)


## Label of the item's own action, or "" when it is only used on the world.
static func get_use_label(item_id: StringName) -> String:
	var definition: Dictionary = get_def(item_id)
	return definition.get("use", "")


static func get_color(item_id: StringName) -> Color:
	var definition: Dictionary = get_def(item_id)
	return definition.get("color", Color.WHITE)


static func get_size(item_id: StringName) -> Vector3:
	var definition: Dictionary = get_def(item_id)
	return definition.get("size", Vector3(0.15, 0.1, 0.15))
