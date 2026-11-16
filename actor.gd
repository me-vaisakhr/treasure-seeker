extends Node3D
## Voxel explorer with jointed limbs (hips, knees, shoulders, elbows).
## Locomotion is procedural: the stride advances with distance covered, so feet
## keep pace with the ground. Hat, backpack and body sit on springs driven by
## the runner's real acceleration, which is what gives the figure weight.
## Scarf and skirt are simulated chains that react to wind and movement.

const Strand := preload("res://strand.gd")

var run := false   # run cycle
var air := false   # mid-jump pose
var hang := false  # hanging from a rope
var pose := ""     # guard, punch, kick, hit, cheer, tuck, vault, slide
var night := false # carries a lit torch
var yaw_goal := NAN  # set by turn_to(): heading being turned towards
var look_up := false # head tilted back (eyeing a rope overhead)
var wounded := false # healing: bandaged head, a little hunched
var bandage: Node3D
var shadow: MeshInstance3D
var floor_y := 0.0   # height of the ground under the runner, where the shadow lies

var main
var t := 0.0
var phase := 0.0
var seed_t := 0.0
var hips: Array[Node3D] = []
var knees: Array[Node3D] = []
var shoulders: Array[Node3D] = []
var elbows: Array[Node3D] = []
var body: Node3D
var head: Node3D
var hat: Node3D
var pack: Node3D
var torch: Node3D
var torch_light: OmniLight3D
var strands: Array[Dictionary] = []

# motion tracking and springs
var last_pos := Vector3.ZERO
var vel := Vector3.ZERO
var moved := false
var hat_y := 0.0
var hat_v := 0.0
var pack_a := 0.0
var pack_v := 0.0
var sq := 0.0     # body squash (negative = compressed)
var sq_v := 0.0


func setup(m, color: Color, tag := "") -> void:
	main = m
	seed_t = m.rng.randf() * 10.0
	var skin := Color("c68e5f")
	var leather := Color("3a2a1c")

	body = Node3D.new()
	body.position.y = 0.58
	add_child(body)
	for side in [-1, 1]:
		# leg: hip -> thigh -> knee -> shin + boot
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.15, 0.58, 0)
		add_child(hip)
		main.box(hip, Vector3(0.2, 0.28, 0.22), Vector3(0, -0.14, 0), skin.darkened(0.08))
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.28, 0)
		hip.add_child(knee)
		main.box(knee, Vector3(0.18, 0.2, 0.2), Vector3(0, -0.1, 0), skin.darkened(0.12))
		main.box(knee, Vector3(0.24, 0.13, 0.32), Vector3(0, -0.245, -0.04), leather)
		hips.append(hip)
		knees.append(knee)
		# arm: shoulder -> upper arm -> elbow -> forearm + hand
		var sh := Node3D.new()
		sh.position = Vector3(side * 0.37, 0.56, 0)
		body.add_child(sh)
		main.box(sh, Vector3(0.17, 0.25, 0.19), Vector3(0, -0.11, 0), color)
		var el := Node3D.new()
		el.position = Vector3(0, -0.24, 0)
		sh.add_child(el)
		main.box(el, Vector3(0.15, 0.22, 0.17), Vector3(0, -0.1, 0), skin)
		main.box(el, Vector3(0.17, 0.1, 0.19), Vector3(0, -0.24, 0), skin.darkened(0.1))
		shoulders.append(sh)
		elbows.append(el)

	main.box(body, Vector3(0.54, 0.58, 0.32), Vector3(0, 0.3, 0), color)
	main.box(body, Vector3(0.57, 0.1, 0.35), Vector3(0, 0.05, 0), leather)
	main.box(body, Vector3(0.12, 0.11, 0.37), Vector3(0, 0.05, 0), Color("e8b530"))
	main.box(body, Vector3(0.08, 0.5, 0.05), Vector3(0.16, 0.32, -0.17), leather)  # strap
	main.box(body, Vector3(0.52, 0.13, 0.4), Vector3(0, 0.63, 0), color)          # scarf

	# backpack hangs from the shoulders and swings on a spring
	pack = Node3D.new()
	pack.position = Vector3(0, 0.62, 0.17)
	body.add_child(pack)
	main.box(pack, Vector3(0.38, 0.42, 0.2), Vector3(0, -0.29, 0.09), Color("7a4f2a"))
	main.box(pack, Vector3(0.46, 0.15, 0.17), Vector3(0, -0.01, 0.1), Color("c9b98a"))
	main.box(pack, Vector3(0.4, 0.2, 0.05), Vector3(0, -0.22, 0.2), color)

	head = Node3D.new()
	head.position = Vector3(0, 0.88, 0)
	body.add_child(head)
	main.box(head, Vector3(0.44, 0.42, 0.42), Vector3.ZERO, skin)
	main.box(head, Vector3(0.46, 0.3, 0.1), Vector3(0, 0.02, 0.19), Color("2b1d14"))
	for side in [-1, 1]:
		main.box(head, Vector3(0.07, 0.09, 0.04), Vector3(side * 0.11, 0.02, -0.22), Color("1a1410"))
	# bandage round the head, shown only while healing
	bandage = Node3D.new()
	head.add_child(bandage)
	main.box(bandage, Vector3(0.47, 0.11, 0.45), Vector3(0, 0.08, 0), Color("f6f1e4"))
	main.box(bandage, Vector3(0.1, 0.1, 0.03), Vector3(0.12, 0.08, 0.23), Color("d6402e"))
	main.box(bandage, Vector3(0.08, 0.2, 0.05), Vector3(-0.2, -0.02, 0.24), Color("f6f1e4"))
	bandage.visible = false
	# hat in the player colour (it is what you see from behind); sits on a spring
	hat = Node3D.new()
	hat.position = Vector3(0, 0.23, 0)
	head.add_child(hat)
	main.box(hat, Vector3(0.72, 0.06, 0.72), Vector3.ZERO, color)
	main.box(hat, Vector3(0.42, 0.2, 0.42), Vector3(0, 0.12, 0), color.darkened(0.1))
	main.box(hat, Vector3(0.44, 0.07, 0.44), Vector3(0, 0.06, 0), Color("fff8e1"))

	# a soft dark shadow on the ground. It is its own object, not part of the
	# body: it stays on the floor when the runner jumps, and shrinks with height.
	shadow = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.46
	disc.bottom_radius = 0.46
	disc.height = 0.02
	disc.radial_segments = 14
	shadow.mesh = disc
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.0, 0.0, 0.0, 0.42)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = sm
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.top_level = true
	add_child(shadow)
	if tag != "":
		var name_tag := Label3D.new()
		name_tag.text = tag
		name_tag.font = main.ui_font
		name_tag.font_size = 54
		name_tag.outline_size = 18
		name_tag.pixel_size = 0.008
		name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_tag.no_depth_test = true
		name_tag.modulate = Color("fff8e1")
		name_tag.position = Vector3(0, 2.5, 0)
		add_child(name_tag)

	# fire torch held out in front, only shown after dark
	torch = Node3D.new()
	torch.position = Vector3(0.42, 0.3, -0.42)
	torch.rotation.x = -0.35
	body.add_child(torch)
	main.box(torch, Vector3(0.08, 0.6, 0.08), Vector3.ZERO, Color("5a3d22"))
	main.box(torch, Vector3.ONE * 0.2, Vector3(0, 0.38, 0), Color("ff9a2e")).material_override = main.mat(Color("ff9a2e"), true)
	main.box(torch, Vector3.ONE * 0.12, Vector3(0, 0.55, 0), Color("ffe066")).material_override = main.mat(Color("ffe066"), true)
	main.flame(torch, Vector3(0, 0.5, 0))
	torch_light = OmniLight3D.new()
	torch_light.position = Vector3(0, 0.6, 0)
	torch_light.light_color = Color("ffb060")
	torch_light.omni_range = 9.0
	torch_light.omni_attenuation = 1.2
	torch.add_child(torch_light)
	torch.visible = false

	# cloth: scarf tail behind the neck, short wrap round the waist
	add_strand(body, Vector3(0.12, 0.63, 0.2), 4, 0.17, Vector2(0.16, 0.04), main.mat(color), Vector3.UP, 1.5, false)
	for k in 8:
		var ang := k * TAU / 8.0
		var out := Vector3(cos(ang), 0, sin(ang))
		var cloth: Color = Color("efe6cf") if k % 2 == 0 else Color("e3d6b4")
		# a short hip wrap: one strip long, so thighs, knees and shins stay in view
		add_strand(self, out * 0.25 + Vector3(0, 0.58, 0), 1, 0.17, Vector2(0.22, 0.04), main.mat(cloth), out, 0.7, true)
	last_pos = position


func add_strand(node: Node3D, local: Vector3, n: int, seg: float, size: Vector2, material: Material, out: Vector3, wind_k: float, collide: bool) -> void:
	var s := Strand.new(self, n, seg, size, material, global_position + local)
	strands.append({"s": s, "node": node, "local": local, "out": out, "w": wind_k, "collide": collide})


func turn_to(yaw: float) -> void:
	# turn smoothly towards a heading instead of snapping
	yaw_goal = yaw


func flash() -> void:
	var tw := create_tween().set_loops(4)
	tw.tween_property(self, "visible", false, 0.06)
	tw.tween_property(self, "visible", true, 0.06)


func _process(delta: float) -> void:
	var dt := minf(delta, 1.0 / 30.0)
	if dt <= 0.0:
		return
	var k := minf(1.0, delta * 16.0)
	t += delta

	# ---- how the figure is really moving this frame
	var step := position - last_pos
	last_pos = position
	if not moved:  # first frame, or just placed somewhere new
		step = Vector3.ZERO
		moved = true
	if step.length() > 3.0:  # teleported (respawn, intro): no kick to the springs
		step = Vector3.ZERO
		floor_y = global_position.y
	var new_vel := step / dt
	var acc := (new_vel - vel) / dt
	vel = new_vel
	var flat := Vector2(step.x, step.z).length()
	var speed := Vector2(vel.x, vel.z).length()
	var fwd := -global_basis.z
	var acc_f := clampf(acc.dot(fwd), -60.0, 60.0)   # along the facing
	var acc_y := clampf(acc.y, -80.0, 80.0)

	if not is_nan(yaw_goal):
		rotation.y = lerp_angle(rotation.y, yaw_goal, minf(1.0, delta * 14.0))
		if absf(angle_difference(rotation.y, yaw_goal)) < 0.02:
			rotation.y = yaw_goal
			yaw_goal = NAN

	# ---- limbs. Angles: positive swings a limb forward, negative back. Knees
	# bend with negative values, elbows with positive.
	var striding := run and not air and not hang and pose == ""
	var amp := 0.0
	if striding:
		# The stride lengthens with speed, as a real runner's does, which keeps
		# the cadence believable (about two cycles a second flat out). Jog on
		# the spot if held still.
		var stride_len := clampf(speed * 0.5, 1.4, 5.0)
		phase += flat * TAU / stride_len if flat > 0.0005 else delta * 11.0
		amp = clampf(speed / 6.0, 0.45, 1.0) if flat > 0.0005 else 0.6
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var ph := phase + (PI if i == 1 else 0.0)
		var thigh := 0.0
		var knee := 0.0
		var arm := 0.04 * side
		var elbow := 0.15
		if striding:
			thigh = sin(ph) * 0.95 * amp
			knee = -(0.15 + 1.15 * maxf(0.0, cos(ph))) * amp  # folds as the leg swings through, straightens to plant
			arm = -sin(ph) * 0.85 * amp
			elbow = 1.15 + sin(ph) * 0.3
		elif hang:
			thigh = sin(t * 5.0 + i * 1.3) * 0.35
			knee = -0.35
			arm = 3.0
			elbow = 0.1
		elif pose == "guard":
			thigh = 0.28 * side
			knee = -0.4
			arm = 1.1
			elbow = 1.6
		elif pose == "punch":
			thigh = 0.55 if i == 0 else -0.4
			knee = -0.5 if i == 0 else -0.1
			arm = 1.6 if i == 0 else 0.8
			elbow = 0.05 if i == 0 else 1.6
		elif pose == "kick":
			thigh = 1.75 if i == 1 else -0.25
			knee = -0.1 if i == 1 else -0.3
			arm = 0.7 * -side
			elbow = 1.0
		elif pose == "hit":
			thigh = 0.3
			knee = -0.7
			arm = -0.9
			elbow = 0.3
		elif pose == "cheer":
			arm = 3.0 + sin(t * 18.0) * 0.25
			elbow = 0.2
		elif pose == "tuck":
			thigh = 1.9
			knee = -2.2
			arm = 1.4
			elbow = 1.6
		elif pose == "vault":
			thigh = 1.3
			knee = -0.6
			arm = 0.5
			elbow = 0.0
		elif pose == "slide":
			thigh = 1.45 if i == 0 else 1.1
			knee = -0.2
			arm = -0.7
			elbow = 0.3
		elif pose == "crouch":  # coiled, ready to spring
			thigh = 0.85
			knee = -1.6
			arm = -0.6
			elbow = 0.7
		elif air:
			thigh = 1.0 if i == 0 else -0.55
			knee = -0.9 if i == 0 else -1.25
			arm = 2.5
			elbow = 0.3
		else:  # standing: weight shifts from foot to foot
			thigh = sin(t * 1.3 + seed_t) * 0.04 * side
			knee = -0.06 - maxf(0.0, sin(t * 1.3 + seed_t) * side) * 0.1
		if night and i == 1 and not air and not hang and pose == "":
			arm = 1.25  # torch arm stays raised
			elbow = 0.3
		# while running the limbs track the cycle closely; smoothing them like a
		# pose change would flatten the stride away
		var lk := minf(1.0, delta * 45.0) if striding else k
		hips[i].rotation.x = lerpf(hips[i].rotation.x, thigh, lk)
		knees[i].rotation.x = lerpf(knees[i].rotation.x, knee, lk)
		shoulders[i].rotation.x = lerpf(shoulders[i].rotation.x, arm, lk)
		elbows[i].rotation.x = lerpf(elbows[i].rotation.x, elbow, lk)
		shoulders[i].rotation.z = lerpf(shoulders[i].rotation.z, side * (0.25 if air or hang else 0.0), k)

	# ---- torso: lean, bob, counter-twist
	var lean := sin(t * 2.0 + seed_t) * 0.02
	var bob := sin(t * 2.2 + seed_t) * 0.015
	var twist := 0.0
	var roll := 0.0
	var look := sin(t * 0.7 + seed_t) * 0.4
	if hang:
		lean = sin(t * 3.0) * 0.18
		look = 0.0
	elif pose == "hit" or pose == "kick":
		lean = 0.4
		look = 0.0
	elif pose == "punch":
		lean = -0.3
		look = 0.0
	elif pose == "guard":
		lean = -0.12
		bob = -0.06
		look = 0.0
	elif pose == "crouch":
		lean = -0.25
		bob = -0.2
		look = 0.0
	elif air:
		lean = -0.28
		look = 0.0
	elif striding:
		lean = -0.1 - 0.2 * amp
		bob = (absf(sin(phase)) * 0.09 - 0.04) * amp  # rises twice per stride, on each push-off
		twist = sin(phase) * 0.16 * amp
		roll = sin(phase) * 0.05 * amp
		look = 0.0
	bandage.visible = wounded
	if wounded and not striding and not air and not hang and pose == "":
		lean -= 0.14  # hunched while hurting
	body.rotation.x = lerpf(body.rotation.x, lean, k)
	body.rotation.y = lerpf(body.rotation.y, twist, k)
	body.rotation.z = lerpf(body.rotation.z, roll, k)
	head.rotation.y = lerpf(head.rotation.y, 0.0 if look_up else look - twist * 0.8, minf(1.0, delta * 6.0))  # head stays level with the path
	head.rotation.x = lerpf(head.rotation.x, 0.55 if look_up else 0.0, minf(1.0, delta * 8.0))

	# ---- springs: weight and follow-through
	# body squash: compresses when a fall is stopped, then rebounds
	sq_v += (-180.0 * sq - 16.0 * sq_v + clampf(-acc_y * 0.006, -4.0, 4.0) * 30.0) * dt
	sq = clampf(sq + sq_v * dt, -0.3, 0.25)
	body.scale = Vector3(1.0 - sq * 0.6, 1.0 + sq, 1.0 - sq * 0.6)
	body.position.y = lerpf(body.position.y, 0.58 + bob + sq * 0.3, k)
	# hat: lifts off the head when the body drops away, thumps back down
	hat_v += (-220.0 * hat_y - 14.0 * hat_v - acc_y * 0.35) * dt
	hat_y = clampf(hat_y + hat_v * dt, -0.03, 0.22)
	hat.position.y = 0.23 + hat_y
	hat.rotation.x = clampf(-acc_f * 0.004, -0.3, 0.3) + hat_y * 0.8
	# backpack: swings back as the runner pulls away, forward as they stop
	pack_v += (-90.0 * pack_a - 9.0 * pack_v + acc_f * 0.9 - acc_y * 0.25) * dt
	pack_a = clampf(pack_a + pack_v * dt, -0.5, 0.7)
	pack.rotation.x = pack_a

	# shadow: lies on the ground the runner last stood on
	if not air and not hang and absf(vel.y) < 0.8:
		floor_y = lerpf(floor_y, global_position.y, minf(1.0, delta * 12.0))
	var lift := maxf(0.0, global_position.y - floor_y)
	var ss := clampf(1.0 - lift * 0.2, 0.35, 1.0)
	shadow.global_transform = Transform3D(Basis.from_scale(Vector3(ss, 1.0, ss)), Vector3(global_position.x, floor_y + 0.035, global_position.z))

	torch.visible = night and not hang
	torch_light.light_energy = 2.0 + sin(t * 17.0) * 0.3 + sin(t * 31.0) * 0.18

	var wind: Vector3 = main.wind(t)
	for d in strands:
		var node: Node3D = d.node
		var out: Vector3 = d.out
		var hint := Vector3.UP if out == Vector3.UP else global_basis * out
		var s: Strand = d.s
		if d.collide:
			s.step(dt, node.to_global(d.local), Vector3(0, -12, 0) + wind * d.w, hint, null, global_position, 0.27)
		else:
			s.step(dt, node.to_global(d.local), Vector3(0, -7, 0) + wind * d.w, hint)
