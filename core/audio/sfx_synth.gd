class_name SfxSynth
extends RefCounted
## Sound effects. The cues people hear most (footsteps, doors, glass, metal,
## rain, thunder) are CC0 recordings in res://audio/sfx (see CREDITS.md), a few
## takes of each so they do not repeat. Everything else, and any cue whose
## files are missing, is synthesised once into an AudioStreamWAV and cached.

const MIX_RATE: int = 22050
const SAMPLE_DIR: String = "res://audio/sfx/"
## Recorded cue -> number of takes (files are <cue>_01.ogg, <cue>_02.ogg ...).
const SAMPLES: Dictionary = {
	&"shoe_step": 8, &"glass_shatter": 6, &"glass_crunch": 3, &"thud": 5, &"knock": 2,
	&"latch_click": 4, &"clatter": 4, &"keys_jingle": 3, &"door_open": 2, &"door_close": 5,
	&"thunder": 1, &"spray": 1, &"rain": 1,
}
const LOOPED_SAMPLES: Array[StringName] = [&"rain"]

static var _cache: Dictionary = {}
static var _samples: Dictionary = {}
static var _last_take: Dictionary = {}


## A random take of a recorded cue (never the same one twice running), or
## null when it has no recordings.
static func _sample(cue: StringName) -> AudioStream:
	var takes: int = SAMPLES.get(cue, 0)
	if takes <= 0:
		return null
	var take: int = randi() % takes
	if takes > 1 and take == int(_last_take.get(cue, -1)):
		take = (take + 1) % takes
	_last_take[cue] = take
	var path: String = "%s%s_%02d.ogg" % [SAMPLE_DIR, cue, take + 1]
	if not _samples.has(path):
		var stream: AudioStream = load(path) as AudioStream if ResourceLoader.exists(path) else null
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = LOOPED_SAMPLES.has(cue)
		_samples[path] = stream
	return _samples[path]


## A stun gun's arc: a harsh buzzing crackle with sharp snaps through it.
static func zap() -> AudioStream:
	return _cached(&"zap", func() -> PackedFloat32Array:
		var length: float = 0.55
		var samples: PackedFloat32Array = _silence(length)
		var phase: float = 0.0
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			phase += TAU * (58.0 + randf_range(-6.0, 6.0)) / MIX_RATE
			var buzz: float = clampf(sin(phase) * 6.0, -1.0, 1.0) * 0.35 + clampf(sin(phase * 3.0) * 4.0, -1.0, 1.0) * 0.15
			var crackle: float = randf_range(-1.0, 1.0) * (0.9 if randf() < 0.08 else 0.25)
			var env: float = minf(t * 300.0, 1.0) * minf((length - t) * 12.0, 1.0)
			samples[i] = (buzz + crackle) * env * 0.8
		return samples)


## A door handle turning and the leaf coming off its latch.
static func door_open() -> AudioStream:
	var recorded: AudioStream = _sample(&"door_open")
	return recorded if recorded != null else latch_click()


## A door pushed shut onto its latch.
static func door_close() -> AudioStream:
	var recorded: AudioStream = _sample(&"door_close")
	return recorded if recorded != null else knock()


## A dry, bright tick: UI clicks and SCUTTLE's legs.
static func click() -> AudioStreamWAV:
	return _cached(&"click", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(0.05)
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var envelope: float = exp(-t * 110.0)
			samples[i] = (sin(TAU * 2600.0 * t) * 0.6 + randf_range(-1.0, 1.0) * 0.5) * envelope
		return samples)


## A UPS alarm chirp: a short square-ish tone.
static func ups_beep() -> AudioStreamWAV:
	return _cached(&"ups_beep", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(0.16)
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var env: float = minf(t * 400.0, 1.0) * minf((0.16 - t) * 300.0, 1.0)
			samples[i] = clampf(sin(TAU * 2950.0 * t) * 3.0, -1.0, 1.0) * 0.35 * env
		return samples)


## Knuckles on a wooden door.
static func knock() -> AudioStream:
	var recorded: AudioStream = _sample(&"knock")
	if recorded != null:
		return recorded
	return _cached(&"knock", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(0.16)
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			samples[i] = (sin(TAU * 150.0 * t) * 0.8 + sin(TAU * 410.0 * t) * 0.3) * exp(-t * 34.0)
		return samples)


## A heavy body slamming a door or a prop landing.
static func thud() -> AudioStream:
	var recorded: AudioStream = _sample(&"thud")
	if recorded != null:
		return recorded
	return _cached(&"thud", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(0.4)
		var low: float = 0.0
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			low = lerpf(low, randf_range(-1.0, 1.0), 0.08)
			samples[i] = (sin(TAU * 62.0 * t) * 0.9 + low * 0.9) * exp(-t * 11.0)
		return samples)


static func glass_shatter() -> AudioStream:
	var recorded: AudioStream = _sample(&"glass_shatter")
	if recorded != null:
		return recorded
	return _cached(&"glass", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(0.9)
		var previous: float = 0.0
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var white: float = randf_range(-1.0, 1.0)
			var high: float = white - previous
			previous = white
			var tinkle: float = sin(TAU * 3100.0 * t) * 0.25 + sin(TAU * 4700.0 * t) * 0.2 + sin(TAU * 6100.0 * t) * 0.15
			samples[i] = high * 0.6 * exp(-t * 7.0) + tinkle * exp(-t * 4.0) * (0.5 + 0.5 * sin(TAU * 23.0 * t))
		return samples)


## Crunch of glass shards underfoot.
static func glass_crunch() -> AudioStream:
	var recorded: AudioStream = _sample(&"glass_crunch")
	if recorded != null:
		return recorded
	return _cached(&"crunch", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(0.22)
		var previous: float = 0.0
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var white: float = randf_range(-1.0, 1.0)
			var gate: float = 1.0 if randf() < 0.35 else 0.15
			samples[i] = (white - previous) * gate * exp(-t * 14.0) * 0.8
			previous = white
		return samples)


## One toll of a bronze bell.
static func bell() -> AudioStreamWAV:
	return _cached(&"bell", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(2.8)
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var tone: float = sin(TAU * 196.0 * t) * 0.5 * exp(-t * 1.1) \
				+ sin(TAU * 392.5 * t) * 0.3 * exp(-t * 1.6) \
				+ sin(TAU * 523.0 * t) * 0.2 * exp(-t * 2.2) \
				+ sin(TAU * 811.0 * t) * 0.15 * exp(-t * 3.4)
			samples[i] = tone * minf(t * 400.0, 1.0)
		return samples)


## Server rack hum (seamless one-second loop).
static func server_hum() -> AudioStreamWAV:
	return _cached(&"hum", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(1.0)
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			samples[i] = sin(TAU * 60.0 * t) * 0.35 + sin(TAU * 120.0 * t) * 0.25 \
				+ sin(TAU * 300.0 * t) * 0.08 + sin(TAU * 1000.0 * t) * 0.03
		return samples)


## Furniture dragged over floor tiles.
static func scrape() -> AudioStreamWAV:
	return _cached(&"scrape", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(0.8)
		var low: float = 0.0
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			low = lerpf(low, randf_range(-1.0, 1.0), 0.2)
			samples[i] = low * (0.6 + 0.4 * sin(TAU * 31.0 * t)) * sin(PI * t / 0.8) * 0.9
		return samples)


## An aluminium window sash rolling along its track: a dry rumble from the
## rollers with grit ticks, rising and falling with the slide (0.9 s).
static func window_slide() -> AudioStreamWAV:
	return _cached(&"window_slide", func() -> PackedFloat32Array:
		var length: float = 0.9
		var samples: PackedFloat32Array = _silence(length)
		var low: float = 0.0
		var mid: float = 0.0
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			low = lerpf(low, randf_range(-1.0, 1.0), 0.06)
			mid = lerpf(mid, randf_range(-1.0, 1.0), 0.35)
			# Speed profile of the slide: breakaway, glide, ease to the stop.
			var speed: float = sin(PI * clampf(t / length, 0.0, 1.0))
			var roller: float = 0.6 + 0.4 * sin(TAU * (38.0 + 22.0 * speed) * t)
			var grit: float = 1.0 if randf() < 0.004 * speed else 0.0
			samples[i] = (low * 0.7 + mid * 0.25) * roller * speed * 0.8 + grit * randf_range(-0.6, 0.6)
		return samples)


## The crescent sash lock snapping over: a small bright metallic click.
static func latch_click() -> AudioStream:
	var recorded: AudioStream = _sample(&"latch_click")
	if recorded != null:
		return recorded
	return _cached(&"latch_click", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(0.09)
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var tick: float = (sin(TAU * 3400.0 * t) * 0.5 + sin(TAU * 1900.0 * t) * 0.4 + randf_range(-1.0, 1.0) * 0.35)
			samples[i] = tick * exp(-t * 90.0) + (sin(TAU * 900.0 * t) * 0.3 * exp(-maxf(t - 0.025, 0.0) * 120.0) if t > 0.025 else 0.0)
		return samples)


## Something metal dropped on tiles (fumbled item, jingling keys).
static func clatter() -> AudioStream:
	var recorded: AudioStream = _sample(&"clatter")
	if recorded != null:
		return recorded
	return _cached(&"clatter", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(0.5)
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var bounce: float = exp(-fmod(t, 0.13) * 40.0) * exp(-t * 5.0)
			samples[i] = (sin(TAU * 1850.0 * t) * 0.4 + sin(TAU * 2930.0 * t) * 0.35 + sin(TAU * 4210.0 * t) * 0.25) * bounce
		return samples)


static func keys_jingle() -> AudioStream:
	var recorded: AudioStream = _sample(&"keys_jingle")
	if recorded != null:
		return recorded
	return _cached(&"keys", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(0.7)
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var shake: float = exp(-fmod(t, 0.09) * 55.0) * sin(PI * t / 0.7)
			samples[i] = (sin(TAU * 3300.0 * t) * 0.35 + sin(TAU * 4450.0 * t) * 0.3 + sin(TAU * 5700.0 * t) * 0.2) * shake
		return samples)


## Running tap water.
static func water() -> AudioStreamWAV:
	return _cached(&"water", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(1.0)
		var band: float = 0.0
		for i: int in samples.size():
			band = lerpf(band, randf_range(-1.0, 1.0), 0.55)
			samples[i] = band * 0.55
		return samples)


## Phone vibration against a desk or a thigh.
static func phone_buzz() -> AudioStreamWAV:
	return _cached(&"buzz", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(0.9)
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var pulse: float = 1.0 if fmod(t, 0.45) < 0.3 else 0.0
			samples[i] = signf(sin(TAU * 170.0 * t)) * 0.25 * pulse
		return samples)


## A single footfall (the hallucinated step behind Juan): a real shoe step.
static func footstep() -> AudioStream:
	return shoe_step()


## A sharp involuntary breath.
static func gasp() -> AudioStreamWAV:
	return _cached(&"gasp", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(0.55)
		var band: float = 0.0
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			band = lerpf(band, randf_range(-1.0, 1.0), 0.45)
			samples[i] = band * sin(PI * t / 0.55) * (0.6 + 0.4 * sin(TAU * 700.0 * t)) * 0.9
		return samples)


## A long roll of thunder: a sharp crack, then the rumble dying away.
static func thunder() -> AudioStream:
	var recorded: AudioStream = _sample(&"thunder")
	if recorded != null:
		return recorded
	return _cached(&"thunder", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(4.5)
		var low: float = 0.0
		var lower: float = 0.0
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			low = lerpf(low, randf_range(-1.0, 1.0), 0.05)
			lower = lerpf(lower, low, 0.02)
			var crack: float = low * exp(-t * 6.0) * 2.2
			var rumble: float = lower * 9.0 * exp(-t * 0.8) * (0.6 + 0.4 * sin(TAU * 0.9 * t + 1.0))
			samples[i] = clampf(crack + rumble, -1.0, 1.0) * minf(t * 60.0, 1.0)
		return samples)


## Steady rain on the roof and the jalousie glass (two-second loop): a dark,
## soft wash with a patter of separate drops on top - not a hiss.
static func rain() -> AudioStream:
	var recorded: AudioStream = _sample(&"rain")
	if recorded != null:
		return recorded
	return _cached(&"rain", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(2.0)
		var low: float = 0.0
		var mid: float = 0.0
		var drop_t: float = 1.0
		var drop_f: float = 3000.0
		var drop_a: float = 0.0
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var white: float = randf_range(-1.0, 1.0)
			low = lerpf(low, white, 0.05)
			mid = lerpf(mid, white, 0.18)
			var wash: float = low * 1.6 + (mid - low) * 0.35
			# Separate drops, about 70 a second, each a tiny bright tick.
			if randf() < 70.0 / MIX_RATE:
				drop_t = 0.0
				drop_f = randf_range(1800.0, 4200.0)
				drop_a = randf_range(0.05, 0.18)
			drop_t += 1.0 / MIX_RATE
			var drop: float = sin(TAU * drop_f * drop_t) * drop_a * exp(-drop_t * 180.0)
			# Fade the first and last few ms so the loop seam is silent-smooth.
			var edge: float = minf(minf(t, 2.0 - t) * 200.0, 1.0)
			samples[i] = (wash * 0.5 + drop) * edge
		return samples)


## A CO2 extinguisher burst: a hard hiss that starts with a pop and tails off.
static func spray() -> AudioStream:
	var recorded: AudioStream = _sample(&"spray")
	if recorded != null:
		return recorded
	return _cached(&"spray", func() -> PackedFloat32Array:
		var length: float = 0.9
		var samples: PackedFloat32Array = _silence(length)
		var previous: float = 0.0
		var band: float = 0.0
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var white: float = randf_range(-1.0, 1.0)
			band = lerpf(band, white - previous * 0.3, 0.6)
			previous = white
			var env: float = minf(t * 80.0, 1.0) * (1.0 - smoothstep(0.55, length, t))
			samples[i] = band * 0.6 * env
		return samples)


## A low, beating drone (four-second loop; every partial completes whole
## cycles in that time, so it loops without a click).
static func drone() -> AudioStreamWAV:
	return _cached(&"drone", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(4.0)
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var swell: float = 0.75 + 0.25 * sin(TAU * 0.25 * t)
			samples[i] = (sin(TAU * 55.0 * t) * 0.4 + sin(TAU * 58.25 * t) * 0.35
				+ sin(TAU * 82.5 * t) * 0.15 + sin(TAU * 116.75 * t) * 0.08) * swell
		return samples)


## One of four rubber-soled steps on terrazzo: a soft heel strike, then the
## toe a beat later, with a touch of grit. Variants stop the machine-gun effect.
static func shoe_step(variant: int = -1) -> AudioStream:
	var recorded: AudioStream = _sample(&"shoe_step")
	if recorded != null:
		return recorded
	var v: int = (randi() if variant < 0 else variant) % 4
	return _cached(StringName("shoe_%d" % v), func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(0.2)
		var band: float = 0.0
		var previous: float = 0.0
		var toe_at: float = randf_range(0.045, 0.07)
		var tone: float = randf_range(85.0, 120.0)
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var white: float = randf_range(-1.0, 1.0)
			band = lerpf(band, white - previous * 0.6, 0.5)
			previous = white
			var heel: float = exp(-t * 60.0)
			var toe: float = exp(-maxf(t - toe_at, 0.0) * 75.0) * 0.55 if t >= toe_at else 0.0
			var body: float = sin(TAU * tone * t) * exp(-t * 45.0) * 0.6
			samples[i] = (band * 0.7 * (heel + toe) + body) * minf(t * 3000.0, 1.0)
		return samples)


## A heavy robot foot coming down: a dull thump through the floor, the ring
## of a hollow aluminium shell, and a short servo whine as the joint settles.
static func metal_step(variant: int = -1) -> AudioStreamWAV:
	var v: int = (randi() if variant < 0 else variant) % 3
	return _cached(StringName("metal_step_%d" % v), func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(0.45)
		var low: float = 0.0
		var detune: float = randf_range(0.94, 1.06)
		var whine_at: float = randf_range(0.06, 0.1)
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			low = lerpf(low, randf_range(-1.0, 1.0), 0.1)
			var thump: float = (sin(TAU * 58.0 * t) * 0.9 + low * 0.8) * exp(-t * 22.0)
			var shell: float = (sin(TAU * 523.0 * detune * t) * 0.3 + sin(TAU * 1347.0 * detune * t) * 0.22
				+ sin(TAU * 2213.0 * detune * t) * 0.14 + sin(TAU * 3480.0 * detune * t) * 0.08) * exp(-t * 18.0)
			var whine: float = 0.0
			if t > whine_at:
				var w: float = t - whine_at
				whine = sin(TAU * (780.0 + 900.0 * w) * w) * 0.12 * sin(PI * clampf(w / 0.25, 0.0, 1.0))
			samples[i] = (thump + shell + whine) * minf(t * 4000.0, 1.0)
		return samples)


## A geared servo motor spinning up and down: the whir a robot makes when it
## starts to move, or turns its head.
static func servo() -> AudioStreamWAV:
	return _cached(&"servo", func() -> PackedFloat32Array:
		var length: float = 0.55
		var samples: PackedFloat32Array = _silence(length)
		var phase: float = 0.0
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var u: float = t / length
			var freq: float = 520.0 + 760.0 * sin(PI * u)
			phase += TAU * freq / MIX_RATE
			# Gear teeth: a buzzy square-ish tone, plus a faint grind.
			var gear: float = clampf(sin(phase) * 2.5, -1.0, 1.0) * 0.22 + sin(phase * 2.0) * 0.12
			var grind: float = randf_range(-1.0, 1.0) * 0.06 * (0.5 + 0.5 * sin(phase * 0.125))
			samples[i] = (gear + grind) * sin(PI * u) * minf(t * 200.0, 1.0)
		return samples)


## The building settling in the cold: a slow metal creak from a duct or a
## door frame somewhere.
static func metal_creak() -> AudioStreamWAV:
	return _cached(&"creak", func() -> PackedFloat32Array:
		var length: float = 1.4
		var samples: PackedFloat32Array = _silence(length)
		var phase: float = 0.0
		var band: float = 0.0
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var u: float = t / length
			# Stick-slip friction: the pitch wanders, and it comes in grains.
			var freq: float = 140.0 + 60.0 * sin(TAU * 0.7 * t) + 25.0 * sin(TAU * 5.3 * t)
			phase += TAU * freq / MIX_RATE
			var grain: float = 0.55 + 0.45 * signf(sin(TAU * 23.0 * t + sin(TAU * 3.1 * t) * 2.0))
			band = lerpf(band, randf_range(-1.0, 1.0), 0.3)
			var tone: float = sin(phase) * 0.5 + sin(phase * 2.01) * 0.25 + sin(phase * 3.03) * 0.12
			samples[i] = (tone + band * 0.15) * grain * sin(PI * u) * 0.8
		return samples)


## One water drop falling into a puddle or a sink.
static func drip() -> AudioStreamWAV:
	return _cached(&"drip", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(0.25)
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var freq: float = 900.0 + 1400.0 * minf(t / 0.03, 1.0)
			samples[i] = sin(TAU * freq * t) * exp(-t * 28.0) * 0.6
		return samples)


## Fire-and-forget positional sound. The player frees itself when finished.
static func play_at(host: Node, stream: AudioStream, position: Vector3, volume_db: float = 0.0,
		pitch: float = 1.0, max_distance: float = 30.0) -> AudioStreamPlayer3D:
	if host == null or not host.is_inside_tree() or stream == null:
		return null
	var scene: Node = host.get_tree().current_scene
	if scene == null:
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = max_distance
	player.unit_size = 4.0
	scene.add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()
	return player


## Fire-and-forget non-positional sound (inside Juan's head, UI, the bell).
static func play_ui(host: Node, stream: AudioStream, volume_db: float = 0.0, pitch: float = 1.0,
		bus: StringName = &"Interface") -> AudioStreamPlayer:
	if host == null or not host.is_inside_tree() or stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	if AudioServer.get_bus_index(bus) >= 0:
		player.bus = bus
	host.get_tree().root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return player


static func _silence(seconds: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(int(seconds * MIX_RATE))
	return samples


const LOOPED_KEYS: Array[StringName] = [&"hum", &"water", &"rain", &"drone"]


## Builds (or fetches) a stream. `generator` returns the mono samples.
static func _cached(key: StringName, generator: Callable) -> AudioStreamWAV:
	if _cache.has(key):
		return _cache[key]
	var samples: PackedFloat32Array = generator.call()
	var stream: AudioStreamWAV = _to_wav(samples, LOOPED_KEYS.has(key))
	_cache[key] = stream
	return stream


static func _to_wav(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream
