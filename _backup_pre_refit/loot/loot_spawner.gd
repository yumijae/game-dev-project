extends Node3D
## Spawns random loot on its Marker3D children when the level starts.
## Each marker carries a "room_type" meta (set by tools/build_school.gd), which
## picks the loot table: computer labs drop electronics, the faculty room drops
## answer keys, the kitchen drops cookware, and so on.
## Move, add or delete markers freely; give new ones a room_type meta.

const LootItem := preload("res://loot/loot_item.gd")

## Chance that each marker gets an item (0..1).
@export_range(0.0, 1.0) var spawn_chance := 0.55
## 0 = different loot every run; any other value = same loot every run.
@export var seed_value := 0

## Which table each room type uses.
const ROOM_TABLES := {
	"admissions": "admin", "cashier": "admin", "records": "admin", "staff": "admin", "lobby": "admin",
	"director": "director",
	"complab": "computer", "server": "server", "mit": "mit",
	"classroom": "classroom",
	"faculty": "faculty",
	"restroom": "restroom",
	"kitchen": "culinary", "pantry": "culinary", "dining": "culinary",
	"roof": "roof",
	"corridor": "classroom",
}

## name, value, rarity, weight (higher = more common), size
const TABLES := {
	"admin": [
		["Stapler", 6, "common", 30, Vector3(0.15, 0.06, 0.05)],
		["Rubber Stamp & Seal", 15, "common", 22, Vector3(0.07, 0.1, 0.07)],
		["Student Records Folder", 40, "uncommon", 18, Vector3(0.24, 0.04, 0.32)],
		["Office Phone", 60, "uncommon", 12, Vector3(0.2, 0.08, 0.18)],
		["Petty Cash Box", 220, "rare", 7, Vector3(0.3, 0.1, 0.22)],
		["Office Laptop", 350, "epic", 3, Vector3(0.34, 0.03, 0.24)],
		["Tuition Payments Envelope", 800, "legendary", 1, Vector3(0.24, 0.03, 0.12)],
	],
	"director": [
		["Fountain Pen", 40, "uncommon", 20, Vector3(0.15, 0.02, 0.02)],
		["Director's Laptop", 400, "epic", 10, Vector3(0.34, 0.03, 0.24)],
		["Gold Wristwatch", 600, "epic", 8, Vector3(0.06, 0.03, 0.06)],
		["Cash Bundle", 500, "epic", 8, Vector3(0.16, 0.05, 0.07)],
		["School Safe Key", 1000, "legendary", 3, Vector3(0.08, 0.01, 0.03)],
	],
	"computer": [
		["Computer Mouse", 15, "common", 30, Vector3(0.07, 0.04, 0.11)],
		["Keyboard", 25, "common", 25, Vector3(0.44, 0.03, 0.14)],
		["USB Drive", 35, "uncommon", 18, Vector3(0.06, 0.02, 0.03)],
		["RAM Stick", 90, "uncommon", 12, Vector3(0.13, 0.01, 0.03)],
		["Solid State Drive", 150, "rare", 8, Vector3(0.1, 0.01, 0.07)],
		["Graphics Card", 450, "epic", 3, Vector3(0.27, 0.05, 0.12)],
	],
	"server": [
		["Network Switch", 120, "rare", 15, Vector3(0.44, 0.05, 0.25)],
		["Router", 90, "uncommon", 15, Vector3(0.25, 0.05, 0.16)],
		["Hard Drive", 80, "uncommon", 20, Vector3(0.15, 0.03, 0.1)],
		["Server Blade", 900, "legendary", 3, Vector3(0.44, 0.05, 0.6)],
	],
	"mit": [
		["Network Cable Bundle", 20, "common", 25, Vector3(0.2, 0.08, 0.2)],
		["Spare Keyboard", 25, "common", 20, Vector3(0.44, 0.03, 0.14)],
		["Solid State Drive", 150, "rare", 12, Vector3(0.1, 0.01, 0.07)],
		["IT Technician's Laptop", 400, "epic", 5, Vector3(0.34, 0.03, 0.24)],
		["Admin Password Notebook", 900, "legendary", 2, Vector3(0.15, 0.02, 0.21)],
	],
	"classroom": [
		["Ballpen Box", 5, "common", 30, Vector3(0.18, 0.04, 0.08)],
		["Notebook", 8, "common", 30, Vector3(0.22, 0.03, 0.28)],
		["Textbook", 15, "common", 22, Vector3(0.2, 0.06, 0.27)],
		["Scientific Calculator", 40, "uncommon", 14, Vector3(0.09, 0.03, 0.17)],
		["Smartphone", 150, "rare", 6, Vector3(0.08, 0.01, 0.16)],
		["Exam Answer Key", 1000, "legendary", 1, Vector3(0.21, 0.02, 0.3)],
	],
	"faculty": [
		["Coffee Mug", 5, "common", 20, Vector3(0.09, 0.1, 0.09)],
		["Class Record Book", 60, "uncommon", 20, Vector3(0.22, 0.03, 0.3)],
		["Projector Remote", 90, "rare", 10, Vector3(0.05, 0.03, 0.15)],
		["Teacher's Laptop", 350, "epic", 6, Vector3(0.34, 0.03, 0.24)],
		["Exam Answer Key", 1000, "legendary", 4, Vector3(0.21, 0.02, 0.3)],
	],
	"restroom": [
		["Toilet Paper", 2, "common", 40, Vector3(0.11, 0.1, 0.11)],
		["Hand Soap", 4, "common", 30, Vector3(0.07, 0.17, 0.07)],
		["Lost Wallet", 180, "rare", 6, Vector3(0.11, 0.02, 0.09)],
	],
	"culinary": [
		["Spice Set", 20, "common", 25, Vector3(0.25, 0.1, 0.08)],
		["Canned Goods", 10, "common", 30, Vector3(0.08, 0.11, 0.08)],
		["Chef's Knife", 70, "uncommon", 15, Vector3(0.33, 0.02, 0.05)],
		["Frying Pan", 50, "uncommon", 15, Vector3(0.3, 0.05, 0.3)],
		["Copper Pot Set", 220, "rare", 6, Vector3(0.35, 0.2, 0.35)],
		["Stand Mixer", 380, "epic", 3, Vector3(0.25, 0.35, 0.3)],
	],
	"roof": [
		["Toolbox", 60, "uncommon", 20, Vector3(0.45, 0.2, 0.2)],
		["Copper Wire Spool", 160, "rare", 10, Vector3(0.3, 0.2, 0.3)],
		["Solar Battery", 300, "epic", 4, Vector3(0.3, 0.2, 0.2)],
	],
}


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	for marker in get_children():
		if not marker is Marker3D:
			continue
		if rng.randf() > spawn_chance:
			continue
		var room_type: String = marker.get_meta("room_type", "classroom")
		var table: Array = TABLES[ROOM_TABLES.get(room_type, "classroom")]
		var row = _pick(rng, table)
		var item := LootItem.new()
		item.item_name = row[0]
		item.value = row[1]
		item.rarity = row[2]
		item.size = row[4]
		item.name = "Loot"
		marker.add_child(item)
		item.rotation.y = rng.randf() * TAU


func _pick(rng: RandomNumberGenerator, table: Array) -> Array:
	var total := 0
	for row in table:
		total += row[3]
	var r := rng.randi_range(1, total)
	for row in table:
		r -= row[3]
		if r <= 0:
			return row
	return table[0]
