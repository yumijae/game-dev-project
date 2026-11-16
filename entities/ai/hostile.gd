class_name Hostile
extends CharacterBody3D
## Base for every threat in the school (the Expo robots). The rest of the game
## only talks to threats through this: doors describe what stands on the far
## side, the player is hit by one, fear rises near one, salt / bottles / the
## extinguisher stun or blind one.
##
## Groups: "hostiles" (every instance) and "hostile_presence" (only while it is
## a real threat - not dormant on its dock or switched off).

## Shown in "___ caught you." and in subtitles.
@export var display_name: String = "Something"
## Stable id for death causes, stats and endings.
@export var hostile_id: StringName = &"hostile"

var stun_time_left: float = 0.0
var blind_time_left: float = 0.0
var is_active: bool = false
## True while it sits on a Com Sci Lab dock recharging (drains the UPS faster).
var is_docked: bool = false


func _enter_tree() -> void:
	add_to_group(&"hostiles")


func _physics_process(delta: float) -> void:
	stun_time_left = maxf(stun_time_left - delta, 0.0)
	blind_time_left = maxf(blind_time_left - delta, 0.0)


## Wakes it up (leaves its dock, starts hunting).
func activate(_at: Vector3 = Vector3.INF) -> void:
	is_active = true
	add_to_group(&"hostile_presence")


## Shuts it down for good (breaker pulled, dawn, ending).
func deactivate() -> void:
	is_active = false
	if is_in_group(&"hostile_presence"):
		remove_from_group(&"hostile_presence")


## WARDEN's circuit lost power (breaker or UPS empty): robots controlled by
## the server shut down; one with its own battery overrides this.
func on_power_cut(_cause: StringName) -> void:
	deactivate()


func is_threatening() -> bool:
	return is_active and stun_time_left <= 0.0


func stun(seconds: float, _cause: StringName = &"") -> void:
	stun_time_left = maxf(stun_time_left, seconds)


func blind(seconds: float) -> void:
	blind_time_left = maxf(blind_time_left, seconds)


func is_blind() -> bool:
	return blind_time_left > 0.0


## What Juan sees through the gap under a door when this is on the far side.
func get_feet_description() -> String:
	return "Something is standing right outside the door."
