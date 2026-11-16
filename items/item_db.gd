class_name ItemDB
extends RefCounted
## Every carryable item in Expo Night. Pure data: ids, display names,
## stack sizes and the tint/size of the placeholder pickup mesh.

const GLASS_BOTTLE: StringName = &"glass_bottle"
const FIRE_EXTINGUISHER: StringName = &"fire_extinguisher"
const SCREWDRIVER: StringName = &"screwdriver"
const TRIPWIRE: StringName = &"tripwire_alarm"
const TABLECLOTH_RAG: StringName = &"tablecloth_rag"
const GAUZE: StringName = &"gauze"
const ALCOHOL: StringName = &"rubbing_alcohol"
const WATER: StringName = &"bottled_water"
const LAN_CABLE: StringName = &"lan_cable"
const BLACKOUT_KIT: StringName = &"blackout_kit"
const CHAIR: StringName = &"monobloc_chair"
const REHAS_KEY: StringName = &"master_rehas_key"
const BOLT_CUTTERS: StringName = &"bolt_cutters"
const CROWBAR: StringName = &"crowbar"
const POWERBANK: StringName = &"powerbank"

## "use" is the label of the item's own action (left click with it in hand).
## A fire extinguisher's count is the number of bursts left in it.
const ITEMS: Dictionary = {
	GLASS_BOTTLE: {"name": "Glass Bottle", "stack": 3, "color": Color(0.6, 0.8, 0.75), "size": Vector3(0.07, 0.22, 0.07),
		"use": "Throw", "desc": "Empty. Throw it and it smashes loudly where it lands - every robot that hears it goes to look."},
	FIRE_EXTINGUISHER: {"name": "Fire Extinguisher", "stack": 3, "color": Color(0.78, 0.08, 0.06), "size": Vector3(0.14, 0.42, 0.14),
		"use": "Spray (one burst)", "desc": "CO2. A burst in a robot's face whites out its sensors: it stops dead for a few seconds and loses you. The number is bursts left."},
	SCREWDRIVER: {"name": "Screwdriver", "stack": 1, "color": Color(0.95, 0.75, 0.1), "size": Vector3(0.2, 0.025, 0.025),
		"desc": "Get close to a robot that can't move - frozen, sprayed or stunned - and pry out its battery (4 s). The tip snaps after one."},
	TRIPWIRE: {"name": "Bottle Tripwire", "stack": 2, "color": Color(0.4, 0.6, 0.7), "size": Vector3(0.16, 0.1, 0.16),
		"use": "Set across the way ahead", "desc": "A bottle balanced on a LAN cable at ankle height. The first robot through knocks it over - you will hear it from far away."},
	TABLECLOTH_RAG: {"name": "Tablecloth Rag", "stack": 2, "color": Color(0.9, 0.9, 0.95), "size": Vector3(0.2, 0.03, 0.2),
		"use": "Disinfect & bandage (7 s)", "desc": "Torn dining linen. Works as a bandage."},
	GAUZE: {"name": "Gauze Roll", "stack": 2, "color": Color(0.96, 0.96, 0.92), "size": Vector3(0.08, 0.06, 0.08),
		"use": "Disinfect & bandage (7 s)", "desc": "From the clinic kit. Needs rubbing alcohol."},
	ALCOHOL: {"name": "Rubbing Alcohol", "stack": 2, "color": Color(0.35, 0.6, 0.9), "size": Vector3(0.07, 0.18, 0.05),
		"use": "Disinfect & bandage (7 s)", "desc": "70% isopropyl. Needs gauze or a tablecloth rag."},
	WATER: {"name": "Bottled Water", "stack": 2, "color": Color(0.5, 0.75, 0.95), "size": Vector3(0.07, 0.2, 0.07),
		"use": "Drink (-35 Panic)", "desc": "Cold water. Steadies the breathing."},
	LAN_CABLE: {"name": "LAN Cable", "stack": 3, "color": Color(0.15, 0.35, 0.8), "size": Vector3(0.16, 0.05, 0.16),
		"desc": "Cat6 from the computer labs. Ties a door handle shut."},
	BLACKOUT_KIT: {"name": "Tape & Black Card", "stack": 3, "color": Color(0.08, 0.08, 0.1), "size": Vector3(0.22, 0.03, 0.3),
		"desc": "Black card paper and packing tape. Tape it over a lab's corridor glass and nothing out there can see in."},
	CHAIR: {"name": "Plastic Chair", "stack": 1, "color": Color(0.92, 0.92, 0.9), "size": Vector3(0.45, 0.8, 0.45),
		"hands_only": true, "desc": "Too big for the backpack. Wedge it under a door handle."},
	REHAS_KEY: {"name": "Master Gate Key", "stack": 1, "color": Color(0.85, 0.7, 0.2), "size": Vector3(0.08, 0.015, 0.03),
		"desc": "Opens the padlock on the Main Lobby roll-up gate."},
	BOLT_CUTTERS: {"name": "Bolt Cutters", "stack": 1, "color": Color(0.7, 0.15, 0.12), "size": Vector3(0.5, 0.05, 0.14),
		"desc": "From the MIT Office. Cuts the gate's chain."},
	CROWBAR: {"name": "Crowbar", "stack": 1, "color": Color(0.2, 0.25, 0.5), "size": Vector3(0.6, 0.04, 0.08),
		"desc": "From the Staff Room. Forces the gate's jammed track."},
	POWERBANK: {"name": "Powerbank", "stack": 1, "color": Color(0.15, 0.15, 0.17), "size": Vector3(0.07, 0.02, 0.14),
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
