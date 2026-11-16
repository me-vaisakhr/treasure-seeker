extends Node3D
## Jungle valley around the path: voxel terrain, trees, palms, bushes, grass,
## a stepped river, waterfalls with mist, and cliff walls. Drawn as MultiMesh batches.

const CELL := 2.0

const FOLIAGE_SHADER := """
shader_type spatial;
uniform sampler2D tex : filter_nearest, repeat_enable;
uniform float strength = 0.1;
uniform float sat = 1.0;
uniform vec3 tint = vec3(1.0);
varying vec3 wpos;
varying vec3 wn;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	float s = sin(TIME * 1.7 + wpos.x * 0.6 + wpos.z * 0.45) + 0.5 * sin(TIME * 3.1 + wpos.z * 1.3);
	VERTEX.x += s * strength * (VERTEX.y + 0.5) / length(MODEL_MATRIX[0].xyz);
}
void fragment() {
	vec3 n = abs(wn);
	vec2 uv = n.y > 0.5 ? wpos.xz : (n.x > 0.5 ? wpos.zy : wpos.xy);
	vec3 a = COLOR.rgb * texture(tex, uv * 0.25).rgb;
	float l = dot(a, vec3(0.3, 0.59, 0.11));
	ALBEDO = mix(vec3(l), a, sat) * tint;  // scenery is muted so the path and players stand out
	ROUGHNESS = 1.0;
}
"""

const WATER_SHADER := """
shader_type spatial;
uniform sampler2D tex : filter_nearest, repeat_enable;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float a = texture(tex, wpos.xz * 0.11 + vec2(0.0, TIME * 0.12)).r;
	float b = texture(tex, wpos.xz * 0.07 + vec2(0.37, -TIME * 0.08)).r;
	float foam = step(1.95, a + b);
	vec3 c = vec3(0.2, 0.58, 0.82) * (0.75 + 0.3 * a);
	ALBEDO = mix(c, vec3(1.0), foam * 0.8);
	EMISSION = ALBEDO * 0.18;
	ROUGHNESS = 0.3;
}
"""

const MIST_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
uniform sampler2D tex : repeat_enable;
uniform vec3 tint : source_color = vec3(0.9, 0.95, 1.0);
uniform float amount = 0.5;
varying vec3 wpos;
varying vec2 lp;
void vertex() {
	lp = VERTEX.xz * 2.0;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	// a soft round bank of mist, wispy inside, fading to nothing at its edge
	float fall = smoothstep(1.0, 0.2, length(lp));
	float n = texture(tex, wpos.xz * 0.03 + vec2(TIME * 0.01, TIME * 0.004)).r;
	ALBEDO = tint;
	ALPHA = fall * (0.3 + 0.7 * n) * amount;
}
"""

const FALL_SHADER := """
shader_type spatial;
uniform sampler2D tex : filter_nearest, repeat_enable;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float a = texture(tex, vec2(wpos.z * 0.25, wpos.y * 0.08 + TIME * 0.9)).r;
	float b = texture(tex, vec2(wpos.z * 0.5 + 0.3, wpos.y * 0.15 + TIME * 1.6)).r;
	float streak = step(1.8, a + b);
	ALBEDO = mix(vec3(0.42, 0.74, 0.95), vec3(1.0), streak * 0.8 + 0.12);
	EMISSION = ALBEDO * 0.28;
	ROUGHNESS = 0.4;
}
"""

var main
var rng: RandomNumberGenerator
var solid_x: Array[Transform3D] = []
var solid_c: Array[Color] = []
var leaf_x: Array[Transform3D] = []
var leaf_c: Array[Color] = []
var water_x: Array[Transform3D] = []
var water_c: Array[Color] = []
var mist_x: Array[Transform3D] = []
var mist_c: Array[Color] = []
var mist_mat: ShaderMaterial
var mpath: Array[Vector3] = []
var mnoise: FastNoiseLite


func add(xs: Array[Transform3D], cs: Array[Color], size: Vector3, at: Vector3, c: Color, basis := Basis.IDENTITY) -> void:
	xs.append(Transform3D(basis * Basis.from_scale(size), at))
	cs.append(c)


func shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex", main.pix_tex)
	return m


func batch(xs: Array[Transform3D], cs: Array[Color], material: Material, shadows := true) -> void:
	if xs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, cs[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = material
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func build(m) -> void:
	main = m
	rng = m.rng
	var path: Array[Vector3] = m.path
	var lo := path[0]
	var hi := path[0]
	for q in path:
		lo = lo.min(q)
		hi = hi.max(q)
	var x0 := lo.x - 14.0
	var x1 := hi.x + 14.0
	var z0 := lo.z - 18.0
	var z1 := hi.z + 14.0
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.07
	# the causeway from the start cave counts as path, so nothing grows on it
	var route: Array[Vector3] = path.duplicate()
	for k in range(1, 8):
		route.append(path[0] + Vector3(0, 0, m.GAP * k))

	# waterfalls pour from the left cliff; a stepped river runs under the right cliff
	var falls: Array[float] = []
	for k in 4:
		falls.append(lerpf(z1 - 12.0, z0 + 12.0, (k + 0.5) / 4.0) + rng.randf_range(-4, 4))
	var fall_base := {}

	var greens: Array[Color] = [Color("2f7a33"), Color("3c9140"), Color("276a2e"), Color("58a83e")]
	var floor_c: Array[Color] = [Color("163a22"), Color("1b4428"), Color("12331e"), Color("204d2c")]
	var gx := x0
	while gx <= x1:
		var gz := z0
		while gz <= z1:
			var d := 1e9
			var py := 0.0
			for q in route:
				var dd := Vector2(q.x - gx, q.z - gz).length()
				if dd < d:
					d = dd
					py = q.y
			var n := noise.get_noise_2d(gx, gz)
			var h := py - 9.5 - clampf((d - 6.0) * 0.3, 0.0, 3.0) + n * 1.5
			var wet := gx > x1 - 9.0  # a long lake under the right-hand mountains
			for fz in falls:
				if gx < x0 + 5.0 and absf(gz - fz) < 4.0:
					wet = true
					fall_base[fz] = py - 14.0
			if wet:
				h = py - 14.0
			h = snappedf(h, 0.5)
			var col := floor_c[clampi(int((n + 1.0) * 2.0), 0, 3)]
			if wet:
				col = Color("6f6a55")
			# soft banks of mist float between the trunks
			if rng.randf() < 0.2:
				var ms := rng.randf_range(9.0, 16.0)
				add(mist_x, mist_c, Vector3(ms, 0.05, ms), Vector3(gx, h + rng.randf_range(2.5, 6.5), gz), Color.WHITE)
			add(solid_x, solid_c, Vector3(CELL, 18, CELL), Vector3(gx, h - 9.0, gz), main.shade(col))
			if wet:
				add(water_x, water_c, Vector3(CELL, 0.3, CELL), Vector3(gx, h + 0.3, gz), Color.WHITE)
				if gx > x1 - 9.0 and rng.randf() < 0.16:  # lotus pads with pink flowers
					add(leaf_x, leaf_c, Vector3(0.9, 0.06, 0.9), Vector3(gx + rng.randf_range(-0.5, 0.5), h + 0.5, gz + rng.randf_range(-0.5, 0.5)), Color("3fa34a"))
					add(leaf_x, leaf_c, Vector3.ONE * 0.24, Vector3(gx, h + 0.66, gz), Color("f7a6c8"))
				if gx > x1 - 9.0 and rng.randf() < 0.08:  # splashes
					spray(Vector3(gx, h + 0.5, gz), Vector3(0.8, 0.1, 0.8), 7, Vector3.UP, 45.0, 1.5, 3.5, -12.0, 0.7, 0.13)
			elif d >= 4.4:  # keep a clear corridor each side of the path
				# plants near the path stay below slab level so they never block the camera
				var room := (py - h - 2.8) if d < 10.0 else 20.0
				_plant(gx, h, gz, room)
			gz += CELL
		gx += CELL

	# Mountains ring the valley: terraced slopes that climb away from it,
	# forested low down, bare rock higher, pale stone at the peaks.
	mpath = path
	mnoise = FastNoiseLite.new()
	mnoise.seed = rng.randi()
	mnoise.frequency = 0.018
	var bottom := lo.y - 20.0
	var blossom: Array[Color] = [Color("e2552e"), Color("e667a5"), Color("8a5fd0"), Color("f2c53a")]
	var mx := x0 - 60.0
	while mx <= x1 + 60.0:
		var mz := z0 - 60.0
		while mz <= z1 + 60.0:
			var dout := maxf(maxf(maxf(x0 - mx, mx - x1), maxf(z0 - mz, mz - z1)), 0.0)
			var in_cave := absf(mx - path[0].x) < 7.0 and mz > z1 - 3.0 and mz < z1 + 16.0  # room for the start cave
			if dout > 0.5 and not in_cave:
				var top := _mount(mx, mz, x0, x1, z0, z1)
				var rel := top - _near_y(clampf(mx, x0, x1), clampf(mz, z0, z1))
				var mn := mnoise.get_noise_2d(mx * 3.0, mz * 3.0)
				var col := greens[clampi(int((mn + 1.0) * 2.0), 0, 3)]
				if rel > 46.0:
					col = Color("cfc8b4")
				elif rel > 28.0:
					col = Color("9c9482")
				elif rel > 14.0 and mn > -0.1:
					col = Color("7d8068")
				add(solid_x, solid_c, Vector3(6.0, top - bottom, 6.0), Vector3(mx, (top + bottom) / 2.0, mz), main.shade(col))
				if rel < 18.0 and rng.randf() < 0.4:  # trees cling to the lower slopes
					var tc := greens[rng.randi_range(0, 3)] if rng.randf() > 0.12 else blossom[rng.randi_range(0, 3)]
					add(leaf_x, leaf_c, Vector3(3.0, 2.2, 3.0), Vector3(mx + rng.randf_range(-1, 1), top + 1.6, mz + rng.randf_range(-1, 1)), main.shade(tc))
					add(solid_x, solid_c, Vector3(0.6, 1.2, 0.6), Vector3(mx, top + 0.4, mz), Color("5e4127"))
			mz += 4.0
		mx += 4.0

	var solid := shader_mat(FOLIAGE_SHADER)  # same pixel shading, no wind sway
	solid.set_shader_parameter("strength", 0.0)
	solid.set_shader_parameter("sat", 0.85)
	solid.set_shader_parameter("tint", Vector3(0.5, 0.62, 0.6))
	batch(solid_x, solid_c, solid)
	var leaves := shader_mat(FOLIAGE_SHADER)
	leaves.set_shader_parameter("sat", 0.95)
	leaves.set_shader_parameter("tint", Vector3(0.36, 0.58, 0.46))
	batch(leaf_x, leaf_c, leaves)
	batch(water_x, water_c, shader_mat(WATER_SHADER))

	# a great temple tower far beyond the gate, a silhouette above the trees
	var tz := z0 - 26.0
	var tx: float = path[path.size() - 1].x
	var tbase := _mount(tx, tz, x0, x1, z0, z1)  # it stands on the mountain side
	for k in 8:
		add(solid_x, solid_c, Vector3(24.0 - k * 2.6, 3.4, 15.0 - k * 1.5), Vector3(tx, tbase + k * 3.4, tz), main.shade(Color("8a6fa0")))
	add(solid_x, solid_c, Vector3(4.0, 2.4, 4.0), Vector3(tx, tbase + 28.6, tz), Color("e8b530"))
	batch(solid_x.slice(solid_x.size() - 9), solid_c.slice(solid_c.size() - 9), solid)

	mist_mat = shader_mat(MIST_SHADER)
	mist_mat.set_shader_parameter("tex", main.noise_tex)
	batch(mist_x, mist_c, mist_mat, false)

	var fall_mat := shader_mat(FALL_SHADER)
	for fz in fall_base:
		var base: float = fall_base[fz]
		var fall_top := _mount(x0 - 4.0, snappedf(fz - z0, 4.0) + z0, x0, x1, z0, z1) - 0.5  # pours off the mountain edge
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, fall_top - base, 4.0)
		mi.mesh = bm
		mi.material_override = fall_mat
		mi.position = Vector3(x0 - 0.7, (fall_top + base) / 2.0, fz)
		add_child(mi)
		var mist := CPUParticles3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3.ONE * 0.3
		mist.mesh = pm
		mist.material_override = main.mat(Color("f2fbff"), true)
		mist.amount = 26
		mist.lifetime = 1.6
		mist.preprocess = 2.0
		mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		mist.emission_box_extents = Vector3(0.8, 0.2, 2.0)
		mist.direction = Vector3(0.6, 1, 0)
		mist.spread = 50.0
		mist.initial_velocity_min = 1.0
		mist.initial_velocity_max = 3.0
		mist.gravity = Vector3(0, -2.5, 0)
		mist.scale_amount_min = 0.4
		mist.scale_amount_max = 1.4
		mist.position = Vector3(x0 + 1.2, base + 0.6, fz)
		add_child(mist)
		# droplets racing down the face, and splash drops kicked out of the pool
		spray(Vector3(x0 - 0.25, fall_top - 1.0, fz), Vector3(0.1, 0.5, 1.9), 30, Vector3.DOWN, 6.0, 9.0, 14.0, -6.0, (fall_top - base) / 13.0, 0.2)
		spray(Vector3(x0 + 1.4, base + 0.5, fz), Vector3(0.6, 0.1, 1.8), 22, Vector3(0.5, 1, 0), 40.0, 3.0, 6.5, -14.0, 0.9, 0.16)


func _near_y(x: float, z: float) -> float:
	var best := 1e9
	var y := 0.0
	for q in mpath:
		var dd := Vector2(q.x - x, q.z - z).length()
		if dd < best:
			best = dd
			y = q.y
	return y


func _mount(x: float, z: float, x0: float, x1: float, z0: float, z1: float) -> float:
	# Mountain surface height: rises with distance outside the valley rectangle.
	var dout := maxf(maxf(maxf(x0 - x, x - x1), maxf(z0 - z, z - z1)), 0.0)
	var py := _near_y(clampf(x, x0, x1), clampf(z, z0, z1))
	var n := mnoise.get_noise_2d(x, z)
	return snappedf(py + 3.0 + dout * (0.8 + 0.5 * n) + absf(mnoise.get_noise_2d(x * 2.3 + 90.0, z * 2.3)) * 9.0, 2.0)


func spray(at: Vector3, extents: Vector3, amount: int, dir: Vector3, spread: float, vmin: float, vmax: float, grav: float, life: float, size: float) -> void:
	var ps := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * size
	ps.mesh = bm
	ps.material_override = main.mat(Color("bfe9ff"), true)
	ps.amount = amount
	ps.lifetime = life
	ps.preprocess = life
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ps.emission_box_extents = extents
	ps.direction = dir
	ps.spread = spread
	ps.initial_velocity_min = vmin
	ps.initial_velocity_max = vmax
	ps.gravity = Vector3(0, grav, 0)
	ps.scale_amount_min = 0.5
	ps.scale_amount_max = 1.2
	ps.position = at
	add_child(ps)


func _plant(x: float, h: float, z: float, room: float) -> void:
	var r := rng.randf()
	x += rng.randf_range(-0.5, 0.5)
	z += rng.randf_range(-0.5, 0.5)
	if r < 0.3 and room > 3.2:  # dense forest
		var th := minf(room, rng.randf_range(5.0, 13.0))
		if rng.randf() < 0.5:
			_palm(x, h, z, th)
		else:
			_tree(x, h, z, th)
	elif r < 0.55:
		var s := rng.randf_range(0.6, 1.1)
		add(leaf_x, leaf_c, Vector3(s * 1.3, s, s * 1.3), Vector3(x, h + s / 2.0, z), main.shade(Color("3f8a34")))
		if rng.randf() < 0.4:
			add(leaf_x, leaf_c, Vector3.ONE * 0.18, Vector3(x + 0.3, h + s + 0.05, z), [Color("ff6b8b"), Color("ffd84a"), Color("ffffff")][rng.randi_range(0, 2)])
	elif r < 0.88:
		for k in 3:
			var gh := rng.randf_range(0.3, 0.7)
			add(leaf_x, leaf_c, Vector3(0.14, gh, 0.14), Vector3(x + rng.randf_range(-0.7, 0.7), h + gh / 2.0, z + rng.randf_range(-0.7, 0.7)), main.shade(Color("72bd4c")))
	elif r < 0.92 and room > 1.6:
		var blocks := mini(int(room / 1.2), rng.randi_range(1, 4))
		for k in blocks:  # ruined pillar stump
			add(solid_x, solid_c, Vector3.ONE * 1.2, Vector3(x, h + 0.6 + k * 1.2, z), main.shade(Color("a89a78")))
		add(leaf_x, leaf_c, Vector3(1.3, 0.25, 1.3), Vector3(x, h + blocks * 1.2 + 0.1, z), main.shade(Color("4f9e3a")))


func _tree(x: float, h: float, z: float, th: float) -> void:
	# Broadleaf: flared roots, a clear trunk, then a crown of leaf clumps that is
	# dark underneath and sun-lit on top, so it reads as a tree from any angle.
	var bark := Color("5e4127")
	var trunk := th * 0.55
	add(solid_x, solid_c, Vector3(0.7, trunk, 0.7), Vector3(x, h + trunk / 2.0, z), main.shade(bark))
	for k in 4:
		var a := k * TAU / 4.0 + 0.4
		add(solid_x, solid_c, Vector3(0.4, 0.7, 0.4), Vector3(x + cos(a) * 0.5, h + 0.35, z + sin(a) * 0.5), main.shade(bark.darkened(0.1)))
	var r := clampf(th * 0.22, 1.3, 2.6)
	var cy := h + trunk + r * 0.5
	var deep := Color("1f6b2e")
	var mid := Color("2f9140")
	var lit := Color("6fcf55")
	if rng.randf() < 0.16:  # in flower: flame-red, pink, purple or yellow
		var bl: Array = [[Color("a3321c"), Color("e2552e"), Color("ff9a4a")], [Color("b0437c"), Color("e667a5"), Color("ffc6dc")], [Color("5f3fa0"), Color("8a5fd0"), Color("d6c0ff")], [Color("b08a1c"), Color("f2c53a"), Color("fff0a0")]][rng.randi_range(0, 3)]
		deep = bl[0]
		mid = bl[1]
		lit = bl[2]
	add(leaf_x, leaf_c, Vector3(r * 2.0, r * 1.2, r * 2.0), Vector3(x, cy, z), main.shade(deep))
	for k in 5:
		var a := k * TAU / 5.0 + rng.randf_range(-0.3, 0.3)
		var s := r * rng.randf_range(0.9, 1.25)
		add(leaf_x, leaf_c, Vector3(s, s * 0.85, s), Vector3(x + cos(a) * r * 0.85, cy + rng.randf_range(-0.3, 0.5), z + sin(a) * r * 0.85), main.shade(mid))
	add(leaf_x, leaf_c, Vector3(r * 1.4, r * 0.7, r * 1.4), Vector3(x, cy + r * 0.75, z), mid.lightened(0.12))
	add(leaf_x, leaf_c, Vector3(r * 0.8, r * 0.45, r * 0.8), Vector3(x + r * 0.2, cy + r * 1.2, z - r * 0.15), lit)
	for k in 3:
		add(leaf_x, leaf_c, Vector3.ONE * 0.4, Vector3(x + rng.randf_range(-r, r), cy + r * 0.9, z + rng.randf_range(-r, r)), lit)


func _palm(x: float, h: float, z: float, th: float) -> void:
	# Coconut palm: a curving ringed trunk, drooping two-part fronds, coconuts.
	var lean := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
	var seg := (th - 0.6) / 5.0
	var top := Vector3(x, h, z)
	for k in 5:
		add(solid_x, solid_c, Vector3(0.4 - k * 0.02, seg, 0.4 - k * 0.02), top + Vector3(0, seg / 2.0, 0), Color("8a6a44") if k % 2 == 0 else Color("75583a"))
		top += Vector3(0, seg, 0) + lean * (k * 0.35)
	for k in 8:
		var yaw := Basis(Vector3.UP, k * TAU / 8.0 + rng.randf_range(-0.2, 0.2))
		var inner := yaw * Basis(Vector3.RIGHT, 0.25)
		var outer := yaw * Basis(Vector3.RIGHT, 0.95)
		var g := Color("3fa34a") if k % 2 == 0 else Color("58b84a")
		add(leaf_x, leaf_c, Vector3(0.6, 0.12, 1.6), top + inner * Vector3(0, 0, -0.8), g, inner)
		add(leaf_x, leaf_c, Vector3(0.45, 0.1, 1.5), top + inner * Vector3(0, 0, -1.6) + outer * Vector3(0, 0, -0.7), g.darkened(0.12), outer)
	add(leaf_x, leaf_c, Vector3(0.6, 0.4, 0.6), top, Color("58b84a"))
	for k in 3:
		add(solid_x, solid_c, Vector3.ONE * 0.28, top + Vector3(cos(k * 2.1) * 0.3, -0.3, sin(k * 2.1) * 0.3), Color("5a3d22"))
