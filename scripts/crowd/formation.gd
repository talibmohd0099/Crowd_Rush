class_name Formation
extends RefCounted
## Formation controller: turns a crowd count into clean local slot offsets.
##
## Slots come from a hexagonal lattice sorted by elliptical distance from the
## centre, so small crowds read as a tight blob (5 = a little diamond), new
## runners always fill the OUTSIDE ring, and big crowds grow deeper instead of
## wider once MAX half-width is reached (the road/gates stay readable).
## Spacing compresses as the crowd grows. Results are cached per count.

const MAX_HALF_WIDTH := 3.1
const SPACING_SMALL := 0.95
const SPACING_LARGE := 0.72

static var _cache: Dictionary = {}


static func spacing_for(n: int) -> float:
	return lerpf(SPACING_SMALL, SPACING_LARGE, clampf((n - 10) / 100.0, 0.0, 1.0))


## Returns local (x, z) offsets, index 0 = centre-most slot. -z is forward.
static func slots(n: int) -> PackedVector2Array:
	if n <= 0:
		return PackedVector2Array()
	if _cache.has(n):
		return _cache[n]
	var s := spacing_for(n)
	# radius a circular blob of n would need; stretch in depth if too wide
	var r := s * sqrt(float(n) * 0.866 / PI) * 1.05
	var elong := 1.0
	if r > MAX_HALF_WIDTH:
		elong = pow(r / MAX_HALF_WIDTH, 2.0)
	var pts: Array[Vector3] = [] # x, z, sort key
	var m := int(ceil(sqrt(float(n)) * 1.6 * elong)) + 3
	for j in range(-m, m + 1):
		var z := float(j) * s * 0.866
		var xoff := 0.5 * s if (j & 1) == 1 else 0.0
		for i in range(-m, m + 1):
			var x := float(i) * s + xoff
			var d := sqrt(x * x + (z / elong) * (z / elong))
			# tiny bias: prefer front + centre so shapes are symmetric-ish and forward-leaning
			var key := d + z * 0.01 + absf(x) * 0.002
			pts.append(Vector3(x, z, key))
	pts.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z < b.z)
	var out := PackedVector2Array()
	var cx := 0.0
	var cz := 0.0
	for k in n:
		out.append(Vector2(pts[k].x, pts[k].y))
		cx += pts[k].x
		cz += pts[k].y
	cx /= n
	cz /= n
	for k in n:
		out[k] = out[k] - Vector2(cx, cz)
	_cache[n] = out
	return out


## Bounds of a formation: x = half width, y = front offset (neg), z = back offset (pos)
static func bounds(n: int) -> Vector3:
	var sl := slots(n)
	var hw := 0.0
	var front := 0.0
	var back := 0.0
	for p in sl:
		hw = maxf(hw, absf(p.x))
		front = minf(front, p.y)
		back = maxf(back, p.y)
	return Vector3(hw + 0.3, front - 0.3, back + 0.3)


## Arc slots wrapped around a target (boss) on the +Z side, in world space.
static func swarm_slots(n: int, target: Vector3, inner_radius: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var ring := 0
	var placed := 0
	while placed < n:
		var r := inner_radius + ring * 0.78
		var arc := deg_to_rad(210.0)
		var cap := maxi(3, int(floor(arc * r / 0.72)))
		var take := mini(cap, n - placed)
		for k in take:
			var f := 0.5 if take == 1 else float(k) / float(take - 1)
			var a := lerpf(-arc * 0.5, arc * 0.5, f) + (0.07 if ring % 2 == 1 else 0.0)
			out.append(target + Vector3(sin(a) * r, 0, cos(a) * r))
		placed += take
		ring += 1
	return out
