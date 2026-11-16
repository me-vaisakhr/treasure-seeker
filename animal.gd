extends Node3D
## Motion rig for the voxel elephant, tiger and cobra (built in animals.gd).
## Like the runners, gaits advance with distance covered, and tails, trunk and
## ears follow through on springs and waves, so the animals move with weight.

var kind := ""

# parts, filled in by animals.gd
var legs: Array[Node3D] = []    # hip pivots: front-left, front-right, back-left, back-right
var shins: Array[Node3D] = []   # knee pivots, same order
var chain: Array[Node3D] = []   # trunk (elephant), tail (tiger), neck (cobra)
var tail: Array[Node3D] = []    # elephant's tail
var ears: Array[Node3D] = []
var arms: Array[Node3D] = []    # monkey: shoulder pivots, left then right
var elbows: Array[Node3D] = []
var coil: Array[Node3D] = []    # cobra body ring
var chest: Node3D
var rump: Node3D
var head: Node3D
var jaw: Node3D
var hood: Node3D
var tongue: Node3D
var neck_root: Node3D
var core: Node3D     # tiger: whole-body pivot, pitched in a leap

# driven from outside
var roar := 0.0      # set to 1 to snap the jaw open; closes by itself
var wake_to := 1.0   # cobra: 0 asleep on its coil, 1 reared up
var strike := 0.0    # cobra: 0..1 lunge
var aim := 0.0       # cobra: yaw (local) towards its target
var crouch := 0.0    # tiger: 0 standing .. 1 low stalking crouch
var hang := false    # monkey: swinging from a vine by its hands
var eat := false     # monkey: munching, one hand to its mouth
var heavy := false   # gorilla: stands on its knuckles, leaning forward
var swipe := 0.0     # tiger: 0..1 one paw strike with the right foreleg

var t := 0.0
var phase := 0.0
var wake := 0.0
var last_pos := Vector3.ZERO
var vel := Vector3.ZERO
var moved := false
var lag := 0.0       # spring: tail / trunk swinging against acceleration
var lag_v := 0.0
var neck_z := 0.0


func _process(delta: float) -> void:
	var dt := minf(delta, 1.0 / 30.0)
	if dt <= 0.0:
		return
	t += delta
	var step := global_position - last_pos
	last_pos = global_position
	if not moved or step.length() > 4.0:
		step = Vector3.ZERO
		moved = true
	var new_vel := step / dt
	var acc := (new_vel - vel) / dt
	vel = new_vel
	var flat := Vector2(step.x, step.z).length()
	var speed := Vector2(vel.x, vel.z).length()
	var acc_f := clampf(acc.dot(-global_basis.z), -50.0, 50.0)
	lag_v += (-70.0 * lag - 9.0 * lag_v + acc_f * 0.6) * dt
	lag = clampf(lag + lag_v * dt, -0.6, 0.6)
	roar = maxf(0.0, roar - delta * 1.1)
	var k := minf(1.0, delta * 14.0)
	match kind:
		"elephant":
			_elephant(delta, flat, speed, k)
		"tiger":
			_tiger(delta, flat, speed, k)
		"cobra":
			_cobra(delta)
		"monkey":
			_monkey(delta, flat, speed, k)


func _elephant(delta: float, flat: float, speed: float, k: float) -> void:
	# Slow rolling walk: diagonal legs move together, the body sways side to
	# side, the head nods, ears fan and the trunk swings like a heavy rope.
	var amp := clampf(speed / 3.0, 0.0, 1.0)
	phase += flat * TAU / 2.6
	var offs := [0.0, PI, PI, 0.0]
	for i in 4:
		var ph: float = phase + offs[i]
		legs[i].rotation.x = lerpf(legs[i].rotation.x, sin(ph) * 0.5 * amp, k)
		shins[i].rotation.x = lerpf(shins[i].rotation.x, -maxf(0.0, cos(ph)) * 0.7 * amp, k)
	chest.rotation.z = lerpf(chest.rotation.z, sin(phase) * 0.05 * amp, k)
	chest.position.y = 1.55 + absf(sin(phase)) * 0.06 * amp + sin(t * 1.4) * 0.012
	head.rotation.x = lerpf(head.rotation.x, sin(phase * 2.0) * 0.06 * amp + sin(t * 0.9) * 0.03 - roar * 0.35, k)
	for i in ears.size():
		var side := -1.0 if i == 0 else 1.0
		ears[i].rotation.y = side * (0.35 + sin(t * 2.4 + i) * 0.28 + amp * 0.2)
	for i in chain.size():  # trunk: hangs, curls at the tip, sways and trails behind motion
		var curl := 0.1 if i < 3 else -0.22
		chain[i].rotation.x = curl + sin(t * 1.7 + i * 0.6) * 0.1 + lag * 0.35 - roar * (0.5 if i < 3 else -0.1)
		chain[i].rotation.z = sin(t * 1.2 + i * 0.5) * 0.08 + sin(phase + i * 0.4) * 0.1 * amp
	for i in tail.size():
		tail[i].rotation.z = sin(t * 3.2 + i * 0.8) * 0.3
		tail[i].rotation.x = 0.12 + lag * 0.3


func _tiger(delta: float, flat: float, speed: float, k: float) -> void:
	# Gallop: front legs reach while the back legs drive, the spine bunches and
	# stretches, the head stays level and the tail streams behind.
	var amp := clampf(speed / 5.0, 0.0, 1.0)
	var airborne := absf(vel.y) > 2.5 and flat > 0.001
	phase += flat * TAU / 2.8
	for i in 4:
		var front := i < 2
		var ph := phase + (0.0 if front else PI * 0.85) + (0.35 if i % 2 == 1 else 0.0)
		var thigh := sin(ph) * 1.05 * amp
		var shin := -maxf(0.0, cos(ph)) * 1.2 * amp
		if airborne:  # a leap: forelegs thrown forward, hind legs trailing
			thigh = 1.15 if front else -1.0
			shin = -0.35 if front else -0.2
		elif amp < 0.05:  # standing: weight low; much lower when stalking
			thigh = (0.12 if front else -0.1) + crouch * (0.55 if front else 0.35)
			shin = -0.3 - crouch * 0.95
		if i == 1 and swipe > 0.0:  # right forepaw lifts high, then rakes down
			thigh = 1.9 * sin(swipe * PI)
			shin = -0.25
		legs[i].rotation.x = lerpf(legs[i].rotation.x, thigh, k)
		shins[i].rotation.x = lerpf(shins[i].rotation.x, shin, k)
	var flex := sin(phase) * 0.2 * amp
	if airborne:
		flex = -0.22
	# in a leap the whole body follows its path: nose up while rising, down to land
	core.rotation.x = lerpf(core.rotation.x, clampf(vel.y * 0.07, -0.6, 0.6) if airborne else 0.0, k)
	flex += roar * 0.1 - crouch * 0.1  # rears back to roar, head and shoulders low to stalk
	chest.rotation.x = lerpf(chest.rotation.x, flex, k)
	rump.rotation.x = lerpf(rump.rotation.x, -flex, k)
	chest.position.y = 0.85 + absf(sin(phase)) * 0.14 * amp + sin(t * 2.0) * 0.012 - crouch * 0.26
	rump.position.y = 0.85 + absf(sin(phase + 0.9)) * 0.12 * amp + sin(t * 2.0 + 0.5) * 0.012 - crouch * 0.12
	head.rotation.x = lerpf(head.rotation.x, -chest.rotation.x + roar * 0.35 - crouch * 0.05, k)  # eyes stay on the prey; head thrown up to roar
	head.rotation.y = sin(t * 0.8) * 0.12 * (1.0 - amp)
	jaw.rotation.x = lerpf(jaw.rotation.x, minf(roar, 1.0) * 0.75, minf(1.0, delta * 22.0))
	for i in chain.size():  # tail: curls up, flicks when idle, whips against the run
		chain[i].rotation.x = -0.14 + sin(t * 3.0 + i * 0.7) * 0.07 + lag * 0.25
		chain[i].rotation.y = sin(t * 2.3 + i * 0.6) * (0.16 - amp * 0.08) + sin(phase + i * 0.5) * 0.12 * amp


func _monkey(delta: float, flat: float, speed: float, k: float) -> void:
	# Hanging: arms stretched up the vine, legs tucked, and the body trails
	# behind the swing like a weight on a string. On the ground it squats,
	# looks about, scratches, and bounds when it moves. Its tail never stops.
	var amp := clampf(speed / 4.0, 0.0, 1.0)
	phase += flat * TAU / 1.4
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var ph := phase + (PI if i == 1 else 0.0)
		var arm := 0.45
		var elbow := 0.5
		var thigh := 1.35  # squatting
		var shin := -2.0
		if heavy:  # knuckle stance: straight arms planted ahead, short bent legs
			arm = 0.42
			elbow = 0.06
			thigh = 0.95
			shin = -1.5
		if hang:
			arm = 3.05 + sin(t * 3.0 + i) * 0.06
			elbow = 0.12
			thigh = 1.1 + sin(t * 4.0 + i * 1.7) * 0.12
			shin = -1.5
		elif amp > 0.1:  # bounding on all fours
			arm = 0.9 + sin(ph) * 0.7
			elbow = 0.3
			thigh = 0.7 - sin(ph) * 0.7
			shin = -1.1
		elif eat and i == 1:  # hand to mouth, munching
			arm = 2.3 + sin(t * 14.0) * 0.12
			elbow = 2.0
		elif heavy and fmod(t, 5.0) < 0.9:  # beats its chest now and then
			arm = 1.5
			elbow = 2.1 + sin(t * 30.0 + i * PI) * 0.35
		elif not heavy and fmod(t + 1.0, 4.0) < 0.9 and i == 0:  # a quick scratch of the ribs
			arm = 0.9
			elbow = 1.9 + sin(t * 26.0) * 0.25
		arms[i].rotation.x = lerpf(arms[i].rotation.x, arm, k)
		arms[i].rotation.z = lerpf(arms[i].rotation.z, side * (0.12 if hang else 0.3), k)
		elbows[i].rotation.x = lerpf(elbows[i].rotation.x, elbow, k)
		legs[i].rotation.x = lerpf(legs[i].rotation.x, thigh, k)
		shins[i].rotation.x = lerpf(shins[i].rotation.x, shin, k)
	var sway := 0.0
	if hang:
		sway = clampf(-lag * 1.6, -0.7, 0.7)  # body lags the swing, then overshoots
	var upright := heavy and fmod(t, 5.0) < 0.9 and not hang and amp < 0.1  # rears up to beat its chest
	var lean := 0.0 if hang else (0.18 if not heavy else (0.12 if upright else 0.5))
	chest.rotation.x = lerpf(chest.rotation.x, sway + lean, k)
	# height that keeps the feet on the ground in each stance
	var rest := 0.62 if hang or amp > 0.1 else (0.66 if heavy else 0.56)
	chest.position.y = lerpf(chest.position.y, rest + (absf(sin(phase)) * 0.12 * amp if not hang else 0.0) + sin(t * 2.4) * 0.012, k)
	head.rotation.y = sin(t * 1.1) * 0.5 * (0.0 if hang or amp > 0.1 else 1.0)
	head.rotation.x = lerpf(head.rotation.x, -sway * 0.6 - lean * 0.8 + (0.25 if eat else 0.0), k)  # keeps looking ahead
	for i in chain.size():  # tail: an S that curls and streams behind a swing
		chain[i].rotation.x = -0.32 + sin(t * 2.6 + i * 0.8) * 0.16 + lag * 0.5
		chain[i].rotation.y = sin(t * 1.9 + i * 0.7) * 0.22


func _cobra(delta: float) -> void:
	# Asleep the neck lies curled forward over the coils. Awake it rears into an
	# S, sways, flares its hood and flicks its tongue. A strike throws the whole
	# neck forward at the target.
	wake = move_toward(wake, wake_to, delta * 2.6)
	var w := smoothstep(0.0, 1.0, wake)
	var s := strike
	neck_root.rotation.y = lerp_angle(neck_root.rotation.y, aim * clampf(w * 0.5 + s, 0.0, 1.0), minf(1.0, delta * 9.0))
	neck_root.position.z = neck_z + s * 0.5
	var up := [-0.3, -0.18, 0.12, 0.3, 0.3]
	for i in chain.size():
		var rx := lerpf(0.36, up[i], w)
		rx = lerpf(rx, 0.3, s)
		rx += sin(t * 1.6 + i * 0.6) * 0.06 * w * (1.0 - s)
		chain[i].rotation.x = rx
		chain[i].rotation.z = sin(t * 2.2 + i * 0.7) * 0.13 * w * (1.0 - s)
	hood.scale.x = lerpf(0.42, 1.0, w) + s * 0.2
	for i in coil.size():  # the body breathes in a slow wave round the ring
		var base: float = coil[i].get_meta("y")
		coil[i].position.y = base + sin(t * 1.8 + i * 0.55) * 0.025
	tongue.scale.z = 1.0 if w > 0.5 and fmod(t + 0.3, 1.1) < 0.18 else 0.12
