class_name MeshFactory
extends RefCounted
## Tiny procedural low-poly mesh toolkit.
## Every primitive is flat shaded and vertex coloured so one shared material can
## render a whole prop. Vertex colour alpha is used as a material "mask"
## (see materials/*.gdshader):
##   a = 1.0 -> tinted by the per-instance colour
##   a = 0.5 -> skin tone (runners only)
##   a = 0.0 -> fixed vertex colour
## Faces are wound automatically: each triangle is flipped if its normal points
## towards the primitive centre, so convex primitives are always correct.

const TINT := 1.0
const SKIN := 0.5
const ACCENT := 0.2 ## runners only: per-runner shoe colour
const FIXED := 0.0


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func commit(st: SurfaceTool) -> ArrayMesh:
	return st.commit()


static func col(c: Color, mask: float = FIXED) -> Color:
	return Color(c.r, c.g, c.b, mask)


## Adds one flat triangle. `inside` is a point inside the solid, used to orient it.
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color, inside: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	var center := (a + b + c) / 3.0
	if n.dot(center - inside) < 0.0:
		var tmp := b
		b = c
		c = tmp
		n = -n
	n = n.normalized()
	# Godot uses clockwise winding for front faces -> emit a, c, b.
	st.set_color(color)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_color(color)
	st.set_normal(n)
	st.add_vertex(c)
	st.set_color(color)
	st.set_normal(n)
	st.add_vertex(b)


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, inside: Vector3) -> void:
	tri(st, a, b, c, color, inside)
	tri(st, a, c, d, color, inside)


## Box (optionally tapered: `top_scale` scales the top face in x/z).
## `xf` places the box: its origin is the box centre.
static func box(st: SurfaceTool, xf: Transform3D, size: Vector3, color: Color, top_scale := Vector2.ONE, top_offset := Vector3.ZERO) -> void:
	var h := size * 0.5
	var tx := h.x * top_scale.x
	var tz := h.z * top_scale.y
	var p: Array[Vector3] = [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-tx, h.y, -tz) + top_offset, Vector3(tx, h.y, -tz) + top_offset,
		Vector3(tx, h.y, tz) + top_offset, Vector3(-tx, h.y, tz) + top_offset,
	]
	for i in p.size():
		p[i] = xf * p[i]
	var inside := xf * (top_offset * 0.5)
	quad(st, p[0], p[1], p[2], p[3], color, inside) # bottom
	quad(st, p[4], p[5], p[6], p[7], color, inside) # top
	quad(st, p[0], p[1], p[5], p[4], color, inside) # front (-z)
	quad(st, p[3], p[2], p[6], p[7], color, inside) # back (+z)
	quad(st, p[1], p[2], p[6], p[5], color, inside) # right
	quad(st, p[0], p[3], p[7], p[4], color, inside) # left


## Convenience: axis aligned box at `center`.
static func box_at(st: SurfaceTool, center: Vector3, size: Vector3, color: Color, top_scale := Vector2.ONE) -> void:
	box(st, Transform3D(Basis(), center), size, color, top_scale)


## Prism / cylinder / cone along local +Y. Origin of `xf` = bottom centre.
static func prism(st: SurfaceTool, xf: Transform3D, r_bottom: float, r_top: float, height: float, sides: int, color: Color, caps := true) -> void:
	var inside := xf * Vector3(0, height * 0.5, 0)
	var bottom: Array[Vector3] = []
	var top: Array[Vector3] = []
	for i in sides:
		var a := TAU * float(i) / float(sides)
		var dir := Vector3(cos(a), 0.0, sin(a))
		bottom.append(xf * (dir * r_bottom))
		top.append(xf * (dir * r_top + Vector3(0, height, 0)))
	var cb := xf * Vector3.ZERO
	var ct := xf * Vector3(0, height, 0)
	for i in sides:
		var j := (i + 1) % sides
		if r_top > 0.0001:
			quad(st, bottom[i], bottom[j], top[j], top[i], color, inside)
		else:
			tri(st, bottom[i], bottom[j], ct, color, inside)
		if caps:
			if r_bottom > 0.0001:
				tri(st, cb, bottom[i], bottom[j], color, inside)
			if r_top > 0.0001:
				tri(st, ct, top[i], top[j], color, inside)


## Smooth-shaded ellipsoid (per-vertex normals) for soft, toy-like parts such
## as the runners' heads. Always closed (full sphere).
static func smooth_sphere(st: SurfaceTool, xf: Transform3D, radii: Vector3, rings: int, segments: int, color: Color) -> void:
	var nb := xf.basis.inverse().transposed()
	var pts: Array = []
	var nrm: Array = []
	for r in rings + 1:
		var phi := lerpf(-PI * 0.5, PI * 0.5, float(r) / float(rings))
		var prow: Array[Vector3] = []
		var nrow: Array[Vector3] = []
		for sg in segments:
			var th := TAU * float(sg) / float(segments)
			var u := Vector3(cos(phi) * cos(th), sin(phi), cos(phi) * sin(th))
			prow.append(xf * (u * radii))
			nrow.append((nb * (u / radii)).normalized())
		pts.append(prow)
		nrm.append(nrow)
	for r in rings:
		for sg in segments:
			var t := (sg + 1) % segments
			var a: Vector3 = pts[r][sg]
			var b: Vector3 = pts[r][t]
			var c: Vector3 = pts[r + 1][t]
			var d: Vector3 = pts[r + 1][sg]
			var na: Vector3 = nrm[r][sg]
			var nb2: Vector3 = nrm[r][t]
			var nc: Vector3 = nrm[r + 1][t]
			var nd: Vector3 = nrm[r + 1][sg]
			if r > 0:
				_tri_n(st, a, b, c, na, nb2, nc, color)
			if r < rings - 1:
				_tri_n(st, a, c, d, na, nc, nd, color)


## Triangle with explicit vertex normals, wound to face along the normals.
static func _tri_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, color: Color) -> void:
	var fn := (b - a).cross(c - a)
	if fn.length_squared() < 1e-14:
		return
	if fn.dot(na + nb + nc) < 0.0:
		var tp := b
		b = c
		c = tp
		var tn := nb
		nb = nc
		nc = tn
	# Godot uses clockwise winding for front faces -> emit a, c, b.
	for v in [[a, na], [c, nc], [b, nb]]:
		st.set_color(color)
		st.set_normal(v[1])
		st.add_vertex(v[0])


## Low-poly ellipsoid (flat shaded). `radii` per axis.
static func sphere(st: SurfaceTool, xf: Transform3D, radii: Vector3, rings: int, segments: int, color: Color, y_min := -1.0, y_max := 1.0) -> void:
	var inside := xf * Vector3.ZERO
	var grid: Array = []
	for r in rings + 1:
		var v := float(r) / float(rings)
		var phi: float = lerp(asin(clampf(y_min, -1.0, 1.0)), asin(clampf(y_max, -1.0, 1.0)), v)
		var row: Array[Vector3] = []
		for s in segments:
			var th := TAU * float(s) / float(segments)
			var p := Vector3(cos(phi) * cos(th) * radii.x, sin(phi) * radii.y, cos(phi) * sin(th) * radii.z)
			row.append(xf * p)
		grid.append(row)
	for r in rings:
		var r0: Array[Vector3] = grid[r]
		var r1: Array[Vector3] = grid[r + 1]
		for s in segments:
			var t := (s + 1) % segments
			var a := r0[s]
			var b := r0[t]
			var c := r1[t]
			var d := r1[s]
			if a.distance_squared_to(b) < 1e-10:
				tri(st, a, c, d, color, inside)
			elif c.distance_squared_to(d) < 1e-10:
				tri(st, a, b, c, color, inside)
			else:
				quad(st, a, b, c, d, color, inside)
	# cap a truncated sphere so it stays closed
	if y_min > -0.999:
		var ring: Array[Vector3] = grid[0]
		var cc := xf * Vector3(0, y_min * radii.y, 0)
		for s in segments:
			tri(st, cc, ring[s], ring[(s + 1) % segments], color, inside)
	if y_max < 0.999:
		var ring2: Array[Vector3] = grid[rings]
		var cc2 := xf * Vector3(0, y_max * radii.y, 0)
		for s in segments:
			tri(st, cc2, ring2[s], ring2[(s + 1) % segments], color, inside)


## Flat quad in the XZ plane (normal +Y) - decals, road markings, shadows.
static func flat_quad(st: SurfaceTool, center: Vector3, size: Vector2, color: Color) -> void:
	var h := Vector3(size.x * 0.5, 0, size.y * 0.5)
	var a := center + Vector3(-h.x, 0, -h.z)
	var b := center + Vector3(h.x, 0, -h.z)
	var c := center + Vector3(h.x, 0, h.z)
	var d := center + Vector3(-h.x, 0, h.z)
	quad(st, a, b, c, d, color, center - Vector3(0, 1, 0))


static func xform(pos: Vector3, euler := Vector3.ZERO, scale := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(euler) * Basis.from_scale(scale), pos)
