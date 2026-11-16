class_name LightRig
extends RefCounted
## One place that decides how every light in the school casts shadows, so no
## source can bleed through the 15 cm partitions or the floor slabs.
##
## Why light leaked before:
##   * Godot's default shadow normal bias (1.0) pushes the shadow lookup
##     further than a partition is thick - light crept under every wall.
##   * The school's merged box meshes cast single-sided shadows, so slab and
##     wall seams let light through from the far side.
##   * Lights without shadows (the phone screen) ignore walls entirely.
##
## Every positional light goes through `seal()`; the building through
## `seal_geometry()`.

## Depth bias tuned for the school's box geometry at the atlas sizes in
## project.godot. Low enough that light stops at the wall face, high enough
## that lit walls do not crawl with acne.
const SHADOW_BIAS: float = 0.03
const SHADOW_NORMAL_BIAS: float = 0.45


## Gives `light` tight, opaque shadows. `softness` is the physical size of the
## emitter in metres (PCSS penumbra): 0 = a hard LED, 0.03 = a candle flame.
## `fog` scales how much the light shows in the volumetric haze - keep it 0
## for lights that sit behind walls the player is not meant to see through.
static func seal(light: Light3D, softness: float = 0.0, fog: float = 0.0) -> void:
	light.shadow_enabled = true
	light.shadow_opacity = 1.0
	light.shadow_bias = SHADOW_BIAS
	light.shadow_normal_bias = SHADOW_NORMAL_BIAS
	light.light_size = softness
	# PCSS already softens the edge; plain PCF blur only for hard emitters.
	light.shadow_blur = 1.0 if softness <= 0.0 else 0.6
	light.light_volumetric_fog_energy = fog
	var omni := light as OmniLight3D
	if omni != null:
		omni.omni_shadow_mode = OmniLight3D.SHADOW_CUBE


## Makes every opaque mesh under `root` cast shadows from both faces, closing
## the seams between merged wall boxes and slabs. Glass and anything already
## set not to cast is left alone so moonlight still falls through windows.
static func seal_geometry(root: Node) -> void:
	for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED


## Light cookie for the phone LED: a hot core, the faint ring a phone's tiny
## reflector throws, and a warm fringe fading to nothing - instead of a flat
## hard-edged disc.
static func led_cookie() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.16, 0.38, 0.5, 0.58, 0.72, 0.86, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0),
		Color(0.96, 0.97, 1.0),
		Color(0.62, 0.64, 0.68),
		Color(0.7, 0.71, 0.74),
		Color(0.46, 0.46, 0.47),
		Color(0.2, 0.19, 0.17),
		Color(0.06, 0.05, 0.035),
		Color(0.0, 0.0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	return texture
