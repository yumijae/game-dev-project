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
	&"glass_shatter": 6, &"glass_crunch": 3, &"thud": 5, &"knock": 2,
	&"latch_click": 4, &"clatter": 4, &"keys_jingle": 3, &"door_open": 2, &"door_close": 5,
	&"thunder": 1, &"spray": 1, &"rain": 1, &"pose_gears": 4,
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


## A taser squeezed with nothing to hit: a short, soft tick-crackle. Low-
## passed and quiet - it must not hurt when spammed (the full zap() is for a
## shot that connects).
static func zap_dry() -> AudioStream:
	return _cached(&"zap_dry", func() -> PackedFloat32Array:
		var length: float = 0.16
		var samples: PackedFloat32Array = _silence(length)
		var phase: float = 0.0
		var lp: float = 0.0
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			phase += TAU * 62.0 / MIX_RATE
			var buzz: float = sin(phase) * 0.5 + sin(phase * 2.0) * 0.2
			var crackle: float = randf_range(-1.0, 1.0) * (0.5 if randf() < 0.04 else 0.12)
			lp += ((buzz + crackle) - lp) * 0.18          # one-pole low-pass, ~700 Hz
			var env: float = minf(t * 400.0, 1.0) * exp(-t * 18.0)
			samples[i] = lp * env * 0.45
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


## Takes of each soft step, so a corridor of them never repeats exactly.
const SOFT_STEP_TAKES: int = 4


## A step in socks: a muffled heel thump and a faint brush of cloth on tile.
## No squeak, no click.
static func sock_step() -> AudioStream:
	return _cached(StringName("sock_step_%d" % (randi() % SOFT_STEP_TAKES)), func() -> PackedFloat32Array:
		var length: float = 0.24
		var samples: PackedFloat32Array = _silence(length)
		var low: float = 0.0
		var band: float = 0.0
		var body: float = randf_range(62.0, 78.0)
		var brush_at: float = randf_range(0.025, 0.04)
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			low = lerpf(low, randf_range(-1.0, 1.0), 0.04)
			band = lerpf(band, randf_range(-1.0, 1.0), 0.25)
			var thump: float = (sin(TAU * body * t) * 0.5 + low * 3.0) * exp(-t * 30.0)
			var brush: float = 0.0
			if t > brush_at:
				var w: float = t - brush_at
				brush = band * 0.18 * minf(w * 60.0, 1.0) * exp(-w * 22.0)
			samples[i] = (thump + brush) * minf(t * 900.0, 1.0) * 0.8
		return samples)


## A bare foot on tile: a soft heel pat, then the ball of the foot a beat
## later. Skin, not rubber: short and dull.
static func bare_step() -> AudioStream:
	return _cached(StringName("bare_step_%d" % (randi() % SOFT_STEP_TAKES)), func() -> PackedFloat32Array:
		var length: float = 0.22
		var samples: PackedFloat32Array = _silence(length)
		var low: float = 0.0
		var pat: float = 0.0
		var body: float = randf_range(80.0, 95.0)
		var ball_at: float = randf_range(0.045, 0.065)
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			low = lerpf(low, randf_range(-1.0, 1.0), 0.06)
			pat = lerpf(pat, randf_range(-1.0, 1.0), 0.18)
			var heel: float = (sin(TAU * body * t) * 0.45 + low * 2.2 + pat * 0.35) * exp(-t * 45.0)
			var ball: float = 0.0
			if t > ball_at:
				var w: float = t - ball_at
				ball = (low * 1.4 + pat * 0.3) * minf(w * 1500.0, 1.0) * exp(-w * 55.0) * 0.6
			samples[i] = (heel + ball) * minf(t * 1500.0, 1.0) * 0.8
		return samples)


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


## A school shoe on tile, synthesised: one of four heel-and-toe steps.
static func shoe_step(variant: int = -1) -> AudioStream:
	var v: int = (randi() if variant < 0 else variant) % SOFT_STEP_TAKES
	return _cached(StringName("shoe_%d" % v), func() -> PackedFloat32Array:
		# A school shoe on tile: a firm heel "tock" (rubber heel, hard floor),
		# then a lighter toe tap. Low and short, so it never squeaks.
		var samples: PackedFloat32Array = _silence(0.22)
		var low: float = 0.0
		var mid: float = 0.0
		var body: float = randf_range(95.0, 120.0)
		var knock_hz: float = randf_range(330.0, 420.0)
		var toe_at: float = randf_range(0.05, 0.07)
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			low = lerpf(low, randf_range(-1.0, 1.0), 0.07)
			mid = lerpf(mid, randf_range(-1.0, 1.0), 0.3)
			var heel: float = (sin(TAU * body * t) * 0.5 + sin(TAU * knock_hz * t) * 0.25 * exp(-t * 30.0)
				+ low * 1.8 + mid * 0.35) * exp(-t * 40.0)
			var toe: float = 0.0
			if t > toe_at:
				var w: float = t - toe_at
				toe = (sin(TAU * body * 1.3 * w) * 0.3 + low * 1.0 + mid * 0.3) * minf(w * 2000.0, 1.0) * exp(-w * 60.0) * 0.55
			samples[i] = (heel + toe) * minf(t * 2500.0, 1.0) * 0.8
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


## A robot's scream as it lunges: two detuned, overdriven sawtooths sweeping
## up, ring-modulated into a metallic shriek, over a burst of grinding noise.
## Play it at a different pitch per robot.
static func screech() -> AudioStreamWAV:
	return _cached(&"screech", func() -> PackedFloat32Array:
		var length: float = 1.25
		var samples: PackedFloat32Array = _silence(length)
		var phase_a: float = 0.0
		var phase_b: float = 0.0
		var phase_ring: float = 0.0
		var hold: float = 0.0
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var u: float = t / length
			var sweep: float = 1.0 - exp(-t * 9.0)
			var freq: float = 260.0 + 900.0 * sweep + 70.0 * sin(TAU * 13.0 * t)
			phase_a = fmod(phase_a + freq / MIX_RATE, 1.0)
			phase_b = fmod(phase_b + freq * 1.497 / MIX_RATE, 1.0)
			phase_ring += TAU * (1830.0 + 400.0 * sin(TAU * 3.0 * t)) / MIX_RATE
			var saws: float = (phase_a * 2.0 - 1.0) * 0.6 + (phase_b * 2.0 - 1.0) * 0.45
			var ring: float = saws * sin(phase_ring)
			# Sample-and-hold grit: a crushed, digital edge.
			if i % 3 == 0:
				hold = saws * 0.6 + ring * 0.7 + randf_range(-1.0, 1.0) * (0.55 * exp(-t * 4.0) + 0.12)
			var env: float = minf(t * 300.0, 1.0) * (1.0 - smoothstep(0.7, 1.0, u))
			samples[i] = tanh(hold * 3.2) * 0.85 * env
		return samples)


# ------------------------------------------------------------- POSE (mannequin)

## One music-box tine: a bright plucked comb tooth with inharmonic overtones,
## two copies a few Hz apart so it beats and sounds out of tune.
static func _tine(t: float, freq: float, decay: float = 6.0) -> float:
	if t < 0.0:
		return 0.0
	var env: float = exp(-t * decay) * minf(t * 3000.0, 1.0)
	var a: float = sin(TAU * freq * t) * 0.5 + sin(TAU * (freq + 4.0) * t) * 0.35
	var over: float = sin(TAU * freq * 2.76 * t) * 0.18 * exp(-t * 14.0) + sin(TAU * freq * 5.4 * t) * 0.1 * exp(-t * 30.0)
	return (a + over) * env


## POSE's footfall: no metal ring - a hollow fibreglass mannequin leg knocking
## the tiles, and the dry tick of a ball joint taking the weight.
## POSE moving: a burst of clockwork gears turning, ending on a click as it
## sets. Recorded (JC Sounds, CC BY 4.0 - see CREDITS.md); falls back to the
## synthesised unfreeze whir if the files are missing.
static func pose_gears() -> AudioStream:
	var recorded: AudioStream = _sample(&"pose_gears")
	if recorded != null:
		return recorded
	return pose_unfreeze()


static func pose_step(variant: int = -1) -> AudioStreamWAV:
	var v: int = (randi() if variant < 0 else variant) % 3
	return _cached(StringName("pose_step_%d" % v), func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(0.3)
		var lo: float = 0.0
		var lo2: float = 0.0
		var body: float = randf_range(0.9, 1.12)
		var tick_at: float = randf_range(0.04, 0.08)
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var n: float = randf_range(-1.0, 1.0)
			lo = lerpf(lo, n, 0.35)
			lo2 = lerpf(lo2, lo, 0.4)
			var knock: float = (sin(TAU * 310.0 * body * t) * 0.5 + sin(TAU * 870.0 * body * t) * 0.32
				+ sin(TAU * 1630.0 * body * t) * 0.16) * exp(-t * 55.0)
			var hollow: float = (lo - lo2) * 1.6 * exp(-t * 60.0)
			var floor_thump: float = sin(TAU * 95.0 * t) * 0.35 * exp(-t * 30.0)
			var tick: float = 0.0
			if t > tick_at and t < tick_at + 0.01:
				tick = randf_range(-1.0, 1.0) * 0.45 * (1.0 - (t - tick_at) / 0.01)
			samples[i] = tanh((knock + hollow + floor_thump + tick) * 1.1) * 0.85 * minf(t * 5000.0, 1.0)
		return samples)


## The moment Juan looks away from POSE: a long hissing intake like breath
## through a plastic mouth, a servo sliding the wrong way (down), and two
## music-box notes a semitone apart - the booth's red-light/green-light tune,
## broken.
static func pose_unfreeze() -> AudioStreamWAV:
	return _cached(&"pose_unfreeze", func() -> PackedFloat32Array:
		var length: float = 0.95
		var samples: PackedFloat32Array = _silence(length)
		var lo: float = 0.0
		var lo2: float = 0.0
		var phase: float = 0.0
		var gate: float = 1.0
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var u: float = t / length
			# Breath: band-passed noise swelling in, fluttering like a throat.
			var n: float = randf_range(-1.0, 1.0)
			lo = lerpf(lo, n, 0.22)
			lo2 = lerpf(lo2, lo, 0.3)
			var flutter: float = 0.65 + 0.35 * sin(TAU * 11.0 * t + sin(TAU * 2.3 * t) * 3.0)
			var breath: float = (lo - lo2) * 2.2 * flutter * pow(sin(PI * clampf(u * 1.15, 0.0, 1.0)), 1.5)
			# Servo dropping in pitch, chopped into stutters.
			var freq: float = 900.0 * exp(-u * 1.1)
			phase += TAU * freq / MIX_RATE
			if i % 600 == 0:
				gate = 1.0 if randf() < 0.7 else 0.0
			var servo_tone: float = clampf(sin(phase) * 2.5, -1.0, 1.0) * 0.12 * gate * sin(PI * u)
			# Broken melody: G6 then F#6, slightly flat.
			var box: float = _tine(t - 0.04, 1554.0, 5.0) * 0.32 + _tine(t - 0.36, 1462.0, 4.0) * 0.3
			samples[i] = tanh((breath * 0.55 + servo_tone + box) * 1.3) * 0.85
		return samples)


## POSE caught mid-move: a porcelain crack as every joint locks at once, a
## short stick-slip creak, and a music-box tooth that jams half-way through
## its note.
static func pose_freeze() -> AudioStreamWAV:
	return _cached(&"pose_freeze", func() -> PackedFloat32Array:
		var length: float = 0.5
		var samples: PackedFloat32Array = _silence(length)
		var lo: float = 0.0
		var cracks: Array[float] = [0.0, randf_range(0.012, 0.025), randf_range(0.03, 0.05), randf_range(0.06, 0.09)]
		var phase: float = 0.0
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var n: float = randf_range(-1.0, 1.0)
			lo = lerpf(lo, n, 0.5)
			var crack: float = 0.0
			for k: int in cracks.size():
				var dt: float = t - cracks[k]
				if dt >= 0.0 and dt < 0.02:
					crack += (n - lo) * exp(-dt * 260.0) * (1.0 if k == 0 else 0.55)
			var creak: float = 0.0
			if t > 0.05 and t < 0.22:
				var w: float = t - 0.05
				phase += TAU * (620.0 - 900.0 * w) / MIX_RATE
				var grain: float = 0.5 + 0.5 * signf(sin(TAU * 48.0 * w))
				creak = sin(phase) * 0.22 * grain * sin(PI * w / 0.17)
			var jam: float = _tine(t - 0.03, 2030.0, 3.0) * 0.3 * (1.0 - smoothstep(0.2, 0.215, t))
			samples[i] = tanh((crack * 1.2 + creak + jam) * 1.4) * 0.9
		return samples)


## POSE losing power: the music box winding down - the tune slowing, sagging
## flat, and stopping on a note that never resolves.
static func pose_slump() -> AudioStreamWAV:
	return _cached(&"pose_slump", func() -> PackedFloat32Array:
		var length: float = 2.4
		var samples: PackedFloat32Array = _silence(length)
		# Red light, green light: E6 G6 E6 C6 D6 B5.
		var notes: Array[float] = [1318.5, 1568.0, 1318.5, 1046.5, 1174.7, 987.8]
		var starts: Array[float] = []
		var at: float = 0.0
		var gap: float = 0.16
		for k: int in notes.size():
			starts.append(at)
			at += gap
			gap *= 1.45
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var s: float = 0.0
			for k: int in notes.size():
				var sag: float = 1.0 - 0.035 * float(k) - 0.02 * maxf(t - starts[k], 0.0)
				s += _tine(t - starts[k], notes[k] * sag, 4.0) * 0.3
			# The spring ratchet clicking slower and slower underneath.
			var rate: float = 18.0 * exp(-t * 1.2)
			var click: float = 0.0
			if fmod(t * rate, 1.0) < 0.04:
				click = randf_range(-1.0, 1.0) * 0.12 * exp(-t * 0.8)
			samples[i] = (s + click) * (1.0 - smoothstep(0.85, 1.0, t / length))
		return samples)


# ----------------------------------------------------------------- PROTOTYPE

## PROTOTYPE's footfall: a sub-bass slam you feel through the floor, the
## chassis clanking on inharmonic, detuned partials, and a grinding knee
## servo groaning down as it straightens.
static func proto_step(variant: int = -1) -> AudioStreamWAV:
	var v: int = (randi() if variant < 0 else variant) % 4
	return _cached(StringName("proto_step_%d" % v), func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(0.65)
		var lo: float = 0.0
		var sub_phase: float = 0.0
		var saw: float = 0.0
		var hold: float = 0.0
		var detune: float = randf_range(0.9, 1.1)
		var grind_at: float = randf_range(0.07, 0.13)
		var grind_hz: float = randf_range(130.0, 175.0)
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			lo = lerpf(lo, randf_range(-1.0, 1.0), 0.06)
			sub_phase += TAU * (48.0 - 18.0 * minf(t / 0.2, 1.0)) / MIX_RATE
			var sub: float = sin(sub_phase) * exp(-t * 8.0)
			var impact: float = lo * 1.3 * exp(-t * 22.0)
			var clank: float = (sin(TAU * 211.0 * detune * t) * 0.24 + sin(TAU * 587.0 * detune * t) * 0.2
				+ sin(TAU * 1093.0 * detune * t) * 0.13 + sin(TAU * 1789.0 * detune * t) * 0.08) * exp(-t * 11.0)
			var grind: float = 0.0
			if t > grind_at:
				var w: float = t - grind_at
				var f: float = grind_hz * exp(-w * 1.8) * (1.0 + 0.08 * randf_range(-1.0, 1.0))
				saw = fmod(saw + f / MIX_RATE, 1.0)
				if i % 4 == 0:
					hold = (saw * 2.0 - 1.0) + randf_range(-1.0, 1.0) * 0.4
				grind = hold * 0.2 * sin(PI * clampf(w / 0.4, 0.0, 1.0))
			samples[i] = tanh((sub + impact + clank + grind) * 1.5) * 0.9 * minf(t * 4000.0, 1.0)
		return samples)


## The buzz PROTOTYPE carries everywhere (seamless two-second loop): a
## harmonic-rich 100 Hz electrical buzz that swells and sags, arcing crackles,
## and twice per loop a glitched, voice-like burst - something trying to talk
## through a shorted speaker.
static func proto_buzz() -> AudioStreamWAV:
	return _cached(&"proto_buzz", func() -> PackedFloat32Array:
		var length: float = 2.0
		var samples: PackedFloat32Array = _silence(length)
		var crackles: Array[float] = []
		for k: int in 9:
			crackles.append(randf_range(0.05, length - 0.08))
		var lo: float = 0.0
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			# Every periodic part fits a whole number of cycles into the loop.
			var swell: float = 0.7 + 0.3 * sin(TAU * 0.5 * t) * sin(TAU * 7.0 * t)
			var buzz: float = clampf(sin(TAU * 100.0 * t) * 3.0, -1.0, 1.0) * 0.22 + sin(TAU * 200.0 * t) * 0.12 \
				+ sin(TAU * 300.0 * t) * 0.1 + sin(TAU * 50.0 * t) * 0.2
			var n: float = randf_range(-1.0, 1.0)
			lo = lerpf(lo, n, 0.5)
			var arc: float = 0.0
			for c: float in crackles:
				var dt: float = t - c
				if dt >= 0.0 and dt < 0.05:
					arc += (n - lo) * exp(-dt * 90.0) * 0.8
			var voice: float = 0.0
			for start: float in [0.55, 1.4]:
				var w: float = t - start
				if w >= 0.0 and w < 0.22:
					var glottis: float = 1.0 if fmod(w * 130.0, 1.0) < 0.3 else -0.25
					var vowel: float = sin(TAU * (650.0 + 450.0 * sin(TAU * 9.0 * w)) * w) * 0.6 + sin(TAU * 1180.0 * w) * 0.35
					var chop: float = 1.0 if fmod(w * 28.0, 1.0) < 0.65 else 0.0
					voice += glottis * vowel * chop * sin(PI * w / 0.22) * 0.32
			samples[i] = tanh((buzz * swell + arc + voice) * 1.4) * 0.75
		return samples)


## PROTOTYPE powering up on its own battery: a grinding groan dragged up from
## sub-bass, stalling and catching, with arcing, ending in a choked shriek.
static func proto_wake() -> AudioStreamWAV:
	return _cached(&"proto_wake", func() -> PackedFloat32Array:
		var length: float = 2.0
		var samples: PackedFloat32Array = _silence(length)
		var saw_a: float = 0.0
		var saw_b: float = 0.0
		var ring: float = 0.0
		var hold: float = 0.0
		var lo: float = 0.0
		var stall: float = 1.0
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var u: float = t / length
			if i % 1500 == 0:
				stall = 0.55 if randf() < 0.3 else 1.0
			var freq: float = 32.0 * pow(5.0, minf(u * 1.25, 1.0)) * stall
			saw_a = fmod(saw_a + freq / MIX_RATE, 1.0)
			saw_b = fmod(saw_b + freq * 1.013 / MIX_RATE, 1.0)
			var groan: float = (saw_a * 2.0 - 1.0) * 0.5 + (saw_b * 2.0 - 1.0) * 0.4
			var n: float = randf_range(-1.0, 1.0)
			lo = lerpf(lo, n, 0.5)
			var arc: float = (n - lo) * 0.6 * (1.0 if fmod(t * 6.3, 1.0) < 0.06 else 0.0)
			var shriek: float = 0.0
			if u > 0.62:
				var w: float = (u - 0.62) / 0.38
				ring += TAU * (1400.0 + 600.0 * sin(TAU * 4.0 * t)) / MIX_RATE
				shriek = groan * sin(ring) * 0.7 * sin(PI * w) * (1.0 if fmod(t * 17.0, 1.0) < 0.7 else 0.2)
			if i % 3 == 0:
				hold = groan + arc + shriek
			var env: float = minf(t * 20.0, 1.0) * (1.0 - smoothstep(0.88, 1.0, u))
			samples[i] = tanh(hold * 2.4) * 0.85 * env
		return samples)


## A spark off PROTOTYPE's torn wiring: a sharp electrical snap, a falling
## zap and a few trailing crackles.
static func arc_snap() -> AudioStreamWAV:
	return _cached(&"arc_snap", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = _silence(0.35)
		var lo: float = 0.0
		var trail: Array[float] = []
		for k: int in randi_range(3, 6):
			trail.append(randf_range(0.03, 0.28))
		for i: int in samples.size():
			var t: float = float(i) / MIX_RATE
			var n: float = randf_range(-1.0, 1.0)
			lo = lerpf(lo, n, 0.45)
			var snap: float = (n - lo) * 1.4 * exp(-t * 90.0)
			var zap: float = clampf(sin(TAU * (1500.0 * exp(-t * 14.0) + 120.0) * t) * 3.0, -1.0, 1.0) * 0.3 * exp(-t * 20.0)
			var crackle: float = 0.0
			for c: float in trail:
				var dt: float = t - c
				if dt >= 0.0 and dt < 0.015:
					crackle += (n - lo) * 0.7 * exp(-dt * 300.0)
			samples[i] = tanh((snap + zap + crackle) * 1.3) * 0.85
		return samples)


## A robot saying `text` aloud: not words, a vocoder-ish chatter, one buzzing
## syllable per vowel group, each through a randomly picked "vowel" filter.
## `base_hz` sets the voice, `grit` (0..1) how broken it sounds, `stutter`
## repeats syllables like a skipping record. Cached per line and voice:
## building one takes ~15 ms, a dropped frame if it happened mid-chase, so
## robots build theirs ahead of time (RobotBase.warm_voice).
static func robot_voice(text: String, base_hz: float, grit: float = 0.2, stutter: bool = false) -> AudioStreamWAV:
	var key := StringName("voice:%d:%s" % [int(base_hz), text])
	if _cache.has(key):
		return _cache[key]
	var stream: AudioStreamWAV = _build_voice(text, base_hz, grit, stutter)
	_cache[key] = stream
	return stream


static func _build_voice(text: String, base_hz: float, grit: float, stutter: bool) -> AudioStreamWAV:
	var syllables: int = 0
	var in_vowel: bool = false
	for c: String in text.to_lower():
		var vowel: bool = "aeiouy".contains(c)
		if vowel and not in_vowel:
			syllables += 1
		in_vowel = vowel
	syllables = clampi(syllables, 2, 18)
	var samples := PackedFloat32Array()
	var phase: float = 0.0
	var formant_phase: float = 0.0
	var k: int = 0
	while k < syllables:
		var dur: float = randf_range(0.085, 0.15)
		var pitch: float = base_hz * randf_range(0.88, 1.14)
		var formant: float = [520.0, 700.0, 900.0, 1250.0, 1700.0].pick_random()
		var count: int = int(dur * MIX_RATE)
		var repeat: int = 2 if stutter and randf() < 0.3 else 1
		for _r: int in repeat:
			for i: int in count:
				var t: float = float(i) / MIX_RATE
				var glide: float = pitch * (1.0 + 0.08 * (1.0 - t / dur))
				phase = fmod(phase + glide / MIX_RATE, 1.0)
				formant_phase += TAU * formant / MIX_RATE
				var buzz: float = clampf((phase * 2.0 - 1.0) * 1.6, -1.0, 1.0)
				var voiced: float = buzz * (0.55 + 0.45 * sin(formant_phase))
				var noise: float = randf_range(-1.0, 1.0) * grit * 0.5
				var env: float = sin(PI * float(i) / float(count))
				var dropout: float = 0.0 if grit > 0.4 and randf() < grit * 0.004 else 1.0
				samples.append(tanh((voiced + noise) * (1.4 + grit * 2.0)) * 0.45 * env * dropout)
		# A short gap between words now and then.
		var gap: float = randf_range(0.01, 0.03) if randf() > 0.25 else randf_range(0.07, 0.12)
		samples.append_array(_silence(gap))
		k += 1
	return _to_wav(samples, false)


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


const LOOPED_KEYS: Array[StringName] = [&"hum", &"water", &"rain", &"drone", &"proto_buzz"]


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
