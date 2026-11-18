class_name Terrain
extends RefCounted
## Shape of the land around the school: the single source of truth for ground
## height outside, so the terrain mesh, its collision, the trees and the
## perimeter all agree. Pure maths, safe from tools, autoloads and AI.
##
## Layout (front of the building faces +Z, the street):
##   * a flat campus pad (y = 0) around the building, the forecourt, the
##     street and the far sidewalk - everything the player can walk on;
##     the street itself runs flat from one edge of the map to the other
##   * beyond it the ground rolls gently into low wooded hills
##   * a creek runs east-west behind the school (the "creek side", -Z)

## Half-size of the whole terrain square, metres.
const EXTENT: float = 110.0
## The flat campus pad: x within +-PAD_X, z from PAD_Z_MIN to PAD_Z_MAX.
const PAD_X: float = Campus.X_MAX + 14.0
const PAD_Z_MIN: float = Campus.Z_MIN - 9.0
const PAD_Z_MAX: float = Campus.Z_MAX + 24.0
## Metres over which the pad blends into the hills.
const BLEND: float = 14.0
## Street centre line and width (the asphalt strip in front of the school).
const STREET_Z: float = Campus.Z_MAX + 12.5
const STREET_WIDTH: float = 9.0
## The creek behind the school: centre line, half width, depth.
const CREEK_Z: float = Campus.Z_MIN - 17.0
const CREEK_HALF_WIDTH: float = 3.0
const CREEK_DEPTH: float = 1.8
## Half width of the low valley the creek runs along (hills flatten into it).
const CREEK_VALLEY: float = 22.0
## Tallest rise of the hills, metres.
const HILL_HEIGHT: float = 7.0

static var _noise: FastNoiseLite = null


static func _hills() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 1904
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 0.018
		_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_noise.fractal_octaves = 3
	return _noise


## Distance (metres) from (x, z) to the flat pad; 0 inside it.
## The street runs flat right across the map (with a 3 m verge each side).
static func pad_distance(x: float, z: float) -> float:
	var dx: float = maxf(absf(x) - PAD_X, 0.0)
	var dz: float = maxf(maxf(PAD_Z_MIN - z, z - PAD_Z_MAX), 0.0)
	var road: float = maxf(absf(z - STREET_Z) - (STREET_WIDTH * 0.5 + 3.0), 0.0)
	return minf(sqrt(dx * dx + dz * dz), road)


## True where the ground is the flat campus pad (y = 0).
static func is_flat(x: float, z: float) -> bool:
	return pad_distance(x, z) <= 0.0


## Ground height at (x, z).
static func height(x: float, z: float) -> float:
	var t: float = smoothstep(0.0, BLEND, pad_distance(x, z))
	var h: float = (_hills().get_noise_2d(x, z) * 0.5 + 0.5) * HILL_HEIGHT * t
	# Low embankment rising towards the edge of the world.
	var edge: float = maxf(absf(x), absf(z)) / EXTENT
	h += smoothstep(0.6, 1.0, edge) * 6.0 * t
	# The creek runs along a broad, low valley: the hills settle towards it
	# and its banks slope gently down to the water.
	var dc: float = absf(z - CREEK_Z)
	h *= smoothstep(CREEK_HALF_WIDTH, CREEK_VALLEY, dc)
	h = lerpf(h, -CREEK_DEPTH, 1.0 - smoothstep(CREEK_HALF_WIDTH * 0.5, CREEK_HALF_WIDTH * 2.4, dc))
	return h


## Surface normal at (x, z) from the height field.
static func normal(x: float, z: float) -> Vector3:
	var e: float = 0.25
	var hx: float = height(x + e, z) - height(x - e, z)
	var hz: float = height(x, z + e) - height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


## True inside the creek bed (water there, nothing planted).
static func is_creek(x: float, z: float) -> bool:
	return absf(z - CREEK_Z) < CREEK_HALF_WIDTH
