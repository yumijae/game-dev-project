class_name RestroomFixture
extends StaticBody3D
## The two things in a restroom that touch Juan's nerves:
##   SINK   - wash his face: -25 Panic, but 3 seconds of running water (6 m).
##   MIRROR - catching his reflection while already Rattled spikes Panic.

enum Kind { SINK, MIRROR }

const LAYER_INTERACT: int = 2
const WASH_TIME: float = 3.0
const WASH_PANIC_RELIEF: float = 25.0
const WASH_NOISE: float = 6.0

@export var kind: Kind = Kind.SINK


static func create(fixture_kind: Kind, volume: Vector3) -> RestroomFixture:
	var fixture := RestroomFixture.new()
	fixture.kind = fixture_kind
	fixture.collision_layer = LAYER_INTERACT
	fixture.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = volume
	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	collider.shape = shape
	fixture.add_child(collider)
	return fixture


func get_interactions(_player: PlayerController) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if kind == Kind.SINK:
		actions.append({"id": &"wash", "label": "Wash your face (3 s, running water)"})
	return actions


func interact(player: PlayerController, action_id: StringName) -> void:
	if kind != Kind.SINK or action_id != &"wash":
		return
	var started: bool = player.start_channel("Washing your face", WASH_TIME, _finish_wash.bind(player), {
		"noise_type": &"water_running", "noise_radius": WASH_NOISE, "noise_interval": 1.0, "can_fumble": false,
	})
	if started:
		var tap: AudioStreamPlayer3D = SfxSynth.play_at(self, SfxSynth.water(), global_position, -6.0)
		if tap != null:
			get_tree().create_timer(player.stats.get_channel_time(WASH_TIME)).timeout.connect(tap.queue_free)


## Called by the player controller the moment the crosshair lands on this.
func on_looked_at(player: PlayerController) -> void:
	if kind == Kind.MIRROR and player.stats.look_in_mirror():
		EventBus.ui_subtitle.emit("Don't. Don't look in the mirror. Something was standing behind me a moment ago.", 4.0, &"Juan")


func _finish_wash(player: PlayerController) -> void:
	player.stats.reduce_panic(WASH_PANIC_RELIEF)
	EventBus.ui_notification.emit("Cold water on your face. Breathe.", 2.5)
