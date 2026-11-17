extends Node3D
## Vault Run prototype: snakes-and-ladders as a temple run.
## 4 players share one path, one die each per turn. Everything is built from boxes in code.

signal rolled
signal never  # never emitted: awaiting it parks a routine for good

const Actor := preload("res://actor.gd")
const Animals := preload("res://animals.gd")
const Nature := preload("res://nature.gd")
const Sfx := preload("res://sfx.gd")
const Strand := preload("res://strand.gd")

const END := 80          # treasure slab
const GAP := 2.4         # distance between slab centres
const JUMP_WINDOW := 0.9 # seconds to tap for a spike jump
const HARMFUL := ["spike", "crumble", "snake", "tiger"]
const HEAL_TURNS := 2     # own turns a wound takes to heal; wounded runners fight worse
const ROLL_TIME := 8.0   # seconds a player has to roll before the turn is lost
const PIXEL := 2          # 3D is rendered at 1/PIXEL resolution for the pixel-art look

const STONE := Color("f2c66e")
const CRUMBLE := Color("8a5f45")
const SNAKE := Color("3f6b3a")
const MYSTERY := Color("7d55c7")
const GOLD := Color("e8b530")
const MOSS := Color("4fae3a")
const DARK := Color("3b4038")

# Style reference: dithered, limited-palette pixel painting. This runs over the
# whole low-res 3D image: richer colour, ordered dithering, soft vignette.
const POST_SHADER := """
shader_type canvas_item;
uniform float levels = 16.0;
uniform float sat = 1.3;
const float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
void fragment() {
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
	vec3 c = texture(TEXTURE, UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, sat);
	vec2 v = UV - 0.5;
	c = pow(c, vec3(1.08)) * 1.1;  // a touch more contrast
	c *= 1.0 - dot(v, v) * 0.35;
	int idx = int(mod(px.x, 4.0)) + int(mod(px.y, 4.0)) * 4;
	float t = ((bayer[idx] + 0.5) / 16.0 - 0.5) * 0.5;
	c = floor(c * levels + 0.5 + t) / levels;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""

# Painted sky: gradient, sun disc and glow, drifting clouds lit from the sun side, stars.
const SKY_SHADER := """
shader_type sky;
uniform vec3 top : source_color;
uniform vec3 horizon : source_color;
uniform vec3 sun_col : source_color;
uniform vec3 cloud_lit : source_color;
uniform vec3 cloud_dark : source_color;
uniform sampler2D noise : repeat_enable;
uniform float coverage = 0.5;
uniform float stars = 0.0;
uniform float flash = 0.0;
void sky() {
	vec3 d = EYEDIR;
	float h = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon, top, pow(h, 0.55));
	float sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
	col += sun_col * (step(0.9985, sd) * 2.5 + pow(sd, 10.0) * 0.4);
	vec2 suv = floor(d.xz / (abs(d.y) + 0.25) * 70.0);
	float st = step(0.993, fract(sin(dot(suv, vec2(12.9898, 78.233))) * 43758.5453));
	col += vec3(st) * stars * step(0.05, d.y);
	vec2 cuv = d.xz / (d.y + 0.2) * 0.13 + vec2(TIME * 0.004, 0.0);
	float n = texture(noise, cuv).r * 0.65 + texture(noise, cuv * 2.3 + 0.4).r * 0.35;
	float edge = 1.0 - coverage;
	float cl = smoothstep(edge, edge + 0.1, n) * smoothstep(0.0, 0.14, d.y);
	vec3 cc = mix(cloud_dark, cloud_lit, clamp(0.35 + sd * 0.8 - smoothstep(edge + 0.1, edge + 0.4, n) * 0.35, 0.0, 1.0));
	col = mix(col, cc, cl * 0.95);
	COLOR = col + vec3(flash);
}
"""

# One day in four keys; the game clock walks through them and loops.
const DAY := [
	{"at": 0.0, "top": "5a6fb5", "hor": "ffb38a", "sun": "ffb07a", "sun_e": 1.25, "amb": "c9a6b0", "amb_e": 0.65, "lit": "ffd9b8", "dark": "b07a9a", "pitch": -14.0, "yaw": 70.0, "night": 0.0},
	{"at": 0.25, "top": "3f8fe0", "hor": "bfe6ff", "sun": "fff4d6", "sun_e": 1.8, "amb": "cfe3ea", "amb_e": 0.8, "lit": "ffffff", "dark": "b9c9de", "pitch": -66.0, "yaw": 25.0, "night": 0.0},
	{"at": 0.5, "top": "5b4a9c", "hor": "ff9a6a", "sun": "ff8a4a", "sun_e": 1.5, "amb": "f0d0c4", "amb_e": 0.9, "lit": "ffc8a8", "dark": "a0609a", "pitch": -12.0, "yaw": -65.0, "night": 0.0},
	{"at": 0.75, "top": "0c1230", "hor": "27356b", "sun": "b4c4ff", "sun_e": 0.75, "amb": "7c90cc", "amb_e": 0.8, "lit": "6a7ab0", "dark": "202a55", "pitch": -55.0, "yaw": -20.0, "night": 1.0},
	{"at": 1.0, "top": "5a6fb5", "hor": "ffb38a", "sun": "ffb07a", "sun_e": 1.25, "amb": "c9a6b0", "amb_e": 0.65, "lit": "ffd9b8", "dark": "b07a9a", "pitch": -14.0, "yaw": 70.0, "night": 0.0},
]
const STYLES := [
	{"name": "Ridge walk", "fwd": Vector2i(5, 8), "side": Vector2i(3, 5), "prof": ["flat", "rolling", "stairs_up", "ledge", "stairs_down", "drop"]},
	{"name": "Zigzag stairs", "fwd": Vector2i(3, 5), "side": Vector2i(4, 7), "prof": ["stairs_up", "stairs_up", "stairs_down", "ledge", "rolling"]},
	{"name": "Long climb", "fwd": Vector2i(7, 11), "side": Vector2i(2, 3), "prof": ["stairs_up", "stairs_up", "ledge", "rolling", "flat", "drop"]},
	{"name": "Rolling hills", "fwd": Vector2i(4, 7), "side": Vector2i(3, 6), "prof": ["rolling", "rolling", "stairs_up", "stairs_down", "drop", "ledge"]},
]

const ROSTER := [
	{"name": "YOU", "color": Color("e2463a"), "off": Vector3(-0.62, 0, 0.45)},
	{"name": "BLUE", "color": Color("3f7fe0"), "off": Vector3(0.0, 0, 0.45)},
	{"name": "GREEN", "color": Color("44b85a"), "off": Vector3(0.62, 0, 0.45)},
	{"name": "PINK", "color": Color("e667b5"), "off": Vector3(-0.62, 0, -0.45)},
	{"name": "GOLD", "color": Color("f2b53a"), "off": Vector3(0.0, 0, -0.45)},
	{"name": "VIOLET", "color": Color("8a5fd0"), "off": Vector3(0.62, 0, -0.45)},
]

var rng := RandomNumberGenerator.new()
var mats := {}
var pix_tex: ImageTexture
var font: Font       # hard-edged, for labels inside the pixel 3D world
var ui_font: Font    # chunky display face for menus and HUD
var tex_cache := {}  # painted UI art from res://ui/, loaded on first use
var rescues: Array[Dictionary] = []  # monkey rescues in flight: {vine, pivot, mk}
var reveals := {}    # slab index -> {nodes, board, radius, shown}: signs appear only when a runner is near
var hurdles := {}    # slab index -> "log" / "block" / "beam": things to vault, flip over or slide under
var view: SubViewport  # low-res 3D viewport
var shake_amt := 0.0
var sfx: Node
var ropes := {}       # rope slab index -> {s: Strand, a: Vector3, b: Vector3}
var wind_fx: Node3D   # follows the camera without turning, so wind keeps one direction
var clock := 0.0
var world: Node3D
var cam: Camera3D
var focus_p: Dictionary = {}
var cam_base := Vector3.ZERO
var cam_dir := Vector3(0, 0, -1)

var path: Array[Vector3] = []  # top-centre of each slab
var dirs: Array[Vector3] = []  # heading from slab i to i+1
var yaws: Array[float] = []
var base_y: Array[float] = []  # path height without the per-slab unevenness (the scenery follows this)

var kinds: Array[String] = []
var rope_to := {}
var snake_to := {}
var slabs: Array[Node3D] = []
var spikes := {}
var players: Array[Dictionary] = []
var finished: Array[Dictionary] = []
var boulder: Node3D
var ball: Node3D
var ball_last := Vector3.ZERO

var bo := -6
var round_no := 0
var jump_open := false
var jump_hit := false
var autoplay := false

var chips: Array[Control] = []
var hud_current: Dictionary = {}
var lbl_hint: Label
var await_roll := false
var pickups := {}   # slab index -> coin / diamond node
var snakes := {}    # slab index -> {neck, tongue, busy}
var env: Environment
var sun: DirectionalLight3D
var style: Dictionary = {}
var bird_in := 2.0
var in_lobby := true
var bot_count := 3
var view_mode := "turn"   # "turn": follow whoever is moving. "mine": stay on my player
var sound_on := true
var lobby: Control
var results: PanelContainer
var hud_nodes: Array[Control] = []
var marker: Node3D        # bouncing arrow over the player whose turn it is
var cam_yaw := PI
var lobby_t := 0.0
var zoom_k := 0.0          # 0 normal camera .. 1 pushed in close on a special move
var zoom_to := 0.0
var zoom_p: Dictionary = {}
var slow_to := 1.0         # game speed wanted (1 normal, lower = slow motion)
var slow_now := 1.0
var dead := false          # this race has been abandoned (restart / exit): all its routines must stop
static var boot_bots := 0  # survives a scene reload: start a race straight away with this many bots
var ui_layer: SubViewport  # the 2D viewport all menus and HUD live in
var safe: Control          # HUD parent, inset to clear the notch and the home bar
var lbl_count: Label       # giant 3-2-1-GO
var pause_btn: Button
var pause_panel: Control
var cine_look_now := Vector3.ZERO
var cine_smooth := 0.0     # >0: the intro camera eases towards its target instead of snapping
var bars: Array[ColorRect] = []  # letterbox bars for the opening
var cine_target: Node3D    # runner the intro camera keeps centred
var skip_intro := false    # set by a tap during the opening
var in_cine := false       # intro: camera is driven by the cut-scene
var cine_pos := Vector3.ZERO
var cine_look := Vector3.ZERO
var stopping := false      # inside a hit-stop freeze
var records: Array = []    # best races, highest score first: {score, place, coins, rounds, bots, date}
var stats := {"races": 0, "wins": 0}
var wallet := 0           # coins banked across games, for the power-up shop
var me_bar: Control       # the human player's own hearts, coins, respawns, shield
var reward_root: Control  # full-screen reward reveal
var reward_rays: Control
var reward_icon: TextureRect
var reward_lbl: Label
var circlers: Array[Node3D] = []
var lbl_big: Label
var lbl_note: Label
var turn_bar: Control
var big_tw: Tween
var msg_tw: Tween
var card: PanelContainer   # what the roll leads to: icon, title, effect
var card_icon: TextureRect
var card_title: Label
var card_sub: Label
var card_tw: Tween
var pin_at := {}      # player name -> where their pin is drawn on the race bar (slabs, eased)
var pin_bo := 0.0     # the boulder's pin
var flash_rect: ColorRect  # full-screen tint when you are hurt or reborn
var note_tw: Tween
var tigers := {}    # slab index -> {node, cool}
var tod := 0.0      # time of day, 0..1 (see DAY)
var night_k := 0.0
var was_night := false
var rain := false
var rain_k := 0.0
var weather_in := 40.0
var thunder_in := 8.0
var flash := 0.0
var sky_mat: ShaderMaterial
var noise_tex: ImageTexture
var rain_fx: CPUParticles3D
var nature: Node3D
var track: Control
var msg_panel: PanelContainer
var die: Control
var die_val := 0
var die_color := Color.WHITE
var lbl_msg: Label
var jump_bar: Control
var btn_row: HBoxContainer


func _ready() -> void:
	rng.randomize()
	autoplay = OS.get_environment("VAULT_AUTOPLAY") != ""
	sfx = Sfx.new()
	add_child(sfx)
	sfx.start_music.call_deferred()
	_build_look()
	_build_env()
	_build_ui()
	apply_safe_area()
	get_viewport().size_changed.connect(apply_safe_area)
	load_settings()
	prepare_world()
	if boot_bots > 0:  # came back from "Restart"
		var n := boot_bots
		boot_bots = 0
		begin(n)
	elif autoplay:
		begin(int(OS.get_environment("VAULT_BOTS")) if OS.has_environment("VAULT_BOTS") else 3)
	else:
		show_lobby()
		if OS.has_environment("VAULT_MENU"):  # dev: open a menu page directly for screenshots
			menu(OS.get_environment("VAULT_MENU"))
	if OS.has_environment("VAULT_ZOO"):  # dev: animals lined up side-on for inspection ("monkey,gorilla,tiger,elephant,cobra")
		lobby.visible = false
		in_lobby = false
		in_cine = true
		var names := OS.get_environment("VAULT_ZOO").split(",")
		var side := dirs[2].cross(Vector3.UP)
		var mid := path[2] + Vector3(0, 0.0, 0)
		cine_pos = mid + side * (3.2 + names.size() * 1.3) + Vector3(0, 1.6, 0)
		cine_look = mid + Vector3(0, 1.0, 0)
		for k in names.size():
			var an: Node3D = Animals.build(names[k], self)
			world.add_child(an)
			an.position = path[2] - dirs[2] * ((k - (names.size() - 1) / 2.0) * 2.4)
			an.rotation.y = atan2(-side.x, -side.z) + 0.5  # three-quarter view towards the camera
			if "wake_to" in an:
				an.wake_to = 1.0
	if OS.has_environment("VAULT_SHOT"):  # dev: save a true screenshot of the window after VAULT_SHOT_AT seconds, then quit
		await get_tree().create_timer(float(OS.get_environment("VAULT_SHOT_AT")) if OS.has_environment("VAULT_SHOT_AT") else 3.0, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("VAULT_SHOT"))
		print("SHOT window=", DisplayServer.window_get_size(), " viewport=", get_viewport().get_visible_rect().size, " safe=", DisplayServer.get_display_safe_area())
		get_tree().quit()


func _build_look() -> void:
	# Low-res 3D viewport scaled up with nearest filtering = chunky pixels.
	var c := SubViewportContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.stretch = true
	c.stretch_shrink = PIXEL
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var post_sh := Shader.new()
	post_sh.code = POST_SHADER
	var post := ShaderMaterial.new()
	post.shader = post_sh
	c.material = post
	add_child(c)
	view = SubViewport.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	c.add_child(view)

	# Shared noise texture: gives every cube face a pixel-art grain.
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for x in 16:
		for y in 16:
			var v: float = [1.0, 0.93, 0.86, 0.78][rng.randi_range(0, 3)]
			img.set_pixel(x, y, Color(v, v, v))
	pix_tex = ImageTexture.create_from_image(img)

	# Default font with smoothing off, so UI text is hard-edged like pixel art.
	var base := ThemeDB.fallback_font as FontFile
	if base:
		var f: FontFile = base.duplicate()
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.hinting = TextServer.HINTING_NORMAL
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		font = f
	else:
		font = ThemeDB.fallback_font
	ui_font = load("res://fonts/LilitaOne-Regular.ttf") if ResourceLoader.exists("res://fonts/LilitaOne-Regular.ttf") else font


# ---------------------------------------------------------------- helpers

func mat(c: Color, glow := false) -> StandardMaterial3D:
	var k := c.to_html() + ("g" if glow else "")
	if not mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.albedo_texture = pix_tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.uv1_triplanar = true
		m.uv1_triplanar_sharpness = 150.0
		m.uv1_scale = Vector3.ONE * 0.25  # one texel = 0.25 m on every cube
		m.roughness = 1.0
		# dissolve when very close to the camera, so posts and arches never block the view
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		m.distance_fade_min_distance = 1.4
		m.distance_fade_max_distance = 3.6
		if glow:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 0.9
		mats[k] = m
	return mats[k]


func shade(c: Color) -> Color:
	return c.darkened(0.11 * rng.randi_range(0, 3))


func box(parent: Node3D, size: Vector3, at: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat(c)
	mi.position = at
	parent.add_child(mi)
	return mi


func slab_pos(i: int) -> Vector3:
	if i < 0:  # run-up behind the start, used by the boulder
		return path[0] + Vector3(0, 0, GAP * -i)
	return path[mini(i, END)]


func spot(p: Dictionary, i: int) -> Vector3:
	var off: Vector3 = p.off
	return slab_pos(i) + off.rotated(Vector3.UP, yaws[clampi(i, 0, END)])


func hop(node: Node3D, to: Vector3, arc: float, dur: float) -> void:
	if dead or not is_inside_tree():
		await never
	var from := node.position
	var flies := arc >= 0.8 and "air" in node
	if flies:
		node.air = true
		sfx.play("jump", -9.0)
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		node.position = from.lerp(to, t) + Vector3(0, sin(t * PI) * arc, 0), 0.0, 1.0, dur)
	await tw.finished
	if flies:
		node.air = false
		sfx.play("land", -5.0)


func wind(t: float) -> Vector3:
	# One shared wind for cloth, ropes, leaves and trees.
	return Vector3(0.94, 0, 0.33) * (2.5 + 1.5 * sin(t * 0.6) + 0.8 * sin(t * 1.9))


func hitstop(sec := 0.07) -> void:
	# A brief freeze on impact makes hits land harder.
	if dead or not is_inside_tree():
		await never
	stopping = true
	Engine.time_scale = 0.05
	await get_tree().create_timer(sec, true, false, true).timeout
	if dead or not is_inside_tree():
		await never
	stopping = false
	Engine.time_scale = slow_now


func spotlight(p: Dictionary, slow := 0.45) -> void:
	# Special move: the camera pushes in on this player and time slows, so the
	# moment is easy to follow. Always paired with spot_off().
	zoom_p = p
	zoom_to = 1.0
	slow_to = slow
	sfx.duck(true)


func spot_off() -> void:
	zoom_to = 0.0
	slow_to = 1.0
	sfx.duck(false)


func flame(parent: Node3D, at: Vector3) -> void:
	var ps := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.13
	ps.mesh = bm
	ps.material_override = mat(Color("ffb347"), true)
	ps.amount = 10
	ps.lifetime = 0.6
	ps.direction = Vector3.UP
	ps.spread = 18.0
	ps.initial_velocity_min = 0.8
	ps.initial_velocity_max = 1.8
	ps.gravity = Vector3(0, 1.5, 0)
	ps.scale_amount_min = 0.3
	ps.scale_amount_max = 1.1
	ps.position = at
	parent.add_child(ps)


# ---- juice: particles, popups, shake, squash

func burst(at: Vector3, c: Color, n := 14, speed := 4.0) -> void:
	var ps := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.18
	ps.mesh = bm
	ps.material_override = mat(c)
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.amount = n
	ps.lifetime = 0.8
	ps.direction = Vector3.UP
	ps.spread = 75.0
	ps.initial_velocity_min = speed * 0.4
	ps.initial_velocity_max = speed
	ps.gravity = Vector3(0, -14, 0)
	ps.scale_amount_min = 0.5
	ps.scale_amount_max = 1.3
	ps.position = at
	world.add_child(ps)
	ps.emitting = true
	get_tree().create_timer(1.6).timeout.connect(ps.queue_free)


func plume(at: Vector3, c: Color, n: int, rise: float, secs: float, glow := false) -> void:
	# a column of particles that streams upward for a while: smoke, sparks, light
	var ps := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.2
	ps.mesh = bm
	ps.material_override = mat(c, glow)
	ps.amount = n
	ps.lifetime = 1.1
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	ps.emission_sphere_radius = 0.5
	ps.direction = Vector3.UP
	ps.spread = 22.0
	ps.initial_velocity_min = rise * 0.5
	ps.initial_velocity_max = rise
	ps.gravity = Vector3(0, 1.0, 0)
	ps.scale_amount_min = 0.4
	ps.scale_amount_max = 1.5
	ps.angular_velocity_min = -200.0
	ps.angular_velocity_max = 200.0
	ps.position = at
	world.add_child(ps)
	ps.emitting = true
	get_tree().create_timer(secs).timeout.connect(func() -> void:
		if is_instance_valid(ps):
			ps.emitting = false)
	get_tree().create_timer(secs + 1.4).timeout.connect(func() -> void:
		if is_instance_valid(ps):
			ps.queue_free())


func popup(at: Vector3, text: String, c: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = 44
	l.outline_size = 18
	l.pixel_size = 0.01
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	l.modulate = c
	l.position = at + Vector3(0, 2.3, 0)
	world.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y + 1.6, 0.9).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)


func shake(amount: float) -> void:
	shake_amt = maxf(shake_amt, amount * 0.5)  # gentler than first tuned


func squash(node: Node3D) -> void:
	node.scale = Vector3(1.25, 0.7, 1.25)
	create_tween().tween_property(node, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func wait(sec: float) -> void:
	if dead or not is_inside_tree():  # race abandoned: go no further
		await never
	await get_tree().create_timer(sec).timeout
	if dead or not is_inside_tree():
		await never


func frame() -> void:
	if dead or not is_inside_tree():
		await never
	await get_tree().process_frame
	if dead or not is_inside_tree():
		await never


func is_bot(p: Dictionary) -> bool:
	return p.bot or autoplay


func active(p: Dictionary) -> bool:
	return not p.out and not p.done


# ---------------------------------------------------------------- world

func _build_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("a8e0e6")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b9d6c2")
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color("a8e0e6")
	env.fog_density = 0.0032
	var we := WorldEnvironment.new()
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var fn := FastNoiseLite.new()
	fn.seed = rng.randi()
	fn.frequency = 0.025
	fn.fractal_octaves = 3
	noise_tex = ImageTexture.create_from_image(fn.get_seamless_image(128, 128))
	var sky_sh := Shader.new()
	sky_sh.code = SKY_SHADER
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = sky_sh
	sky_mat.set_shader_parameter("noise", noise_tex)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.fog_sky_affect = 0.2
	we.environment = env
	view.add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_color = Color("ffe2a8")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	view.add_child(sun)

	cam = Camera3D.new()
	cam.fov = 62
	cam.far = 260
	view.add_child(cam)

	# slow drifting dust motes around the camera
	var motes := CPUParticles3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3.ONE * 0.07
	motes.mesh = mm
	motes.material_override = mat(Color("fff3c4"), true)
	motes.amount = 50
	motes.lifetime = 7.0
	motes.preprocess = 7.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(7, 4, 9)
	motes.position = Vector3(0, -1, -9)
	motes.gravity = Vector3(0, 0.15, 0)
	motes.initial_velocity_max = 0.4
	motes.spread = 180.0
	cam.add_child(motes)

	wind_fx = Node3D.new()
	view.add_child(wind_fx)
	# [colour, count, mesh size, speed min, speed max, emitter offset, emitter half-size]
	var blown := [
		[Color("6fbf4a"), 26, Vector3(0.16, 0.03, 0.11), 1.5, 4.0, Vector3(-6, 2, -8), Vector3(9, 5, 11)],
		[Color("e0b040"), 12, Vector3(0.16, 0.03, 0.11), 1.5, 4.0, Vector3(-6, 2, -8), Vector3(9, 5, 11)],
		[Color("e6d3a3"), 16, Vector3(0.5, 0.04, 0.04), 5.0, 8.0, Vector3(-7, -3.5, -8), Vector3(8, 1.2, 11)],
	]
	for b in blown:
		var ps := CPUParticles3D.new()
		var bm := BoxMesh.new()
		bm.size = b[2]
		ps.mesh = bm
		ps.material_override = mat(b[0])
		ps.amount = b[1]
		ps.lifetime = 5.0
		ps.preprocess = 5.0
		ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		ps.emission_box_extents = b[6]
		ps.position = b[5]
		ps.direction = Vector3(0.94, -0.12, 0.33)
		ps.spread = 16.0
		ps.initial_velocity_min = b[3]
		ps.initial_velocity_max = b[4]
		ps.gravity = Vector3(0, -0.5, 0)
		ps.angular_velocity_min = -300.0
		ps.angular_velocity_max = 300.0
		wind_fx.add_child(ps)

	rain_fx = CPUParticles3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.035, 0.8, 0.035)
	rain_fx.mesh = rm
	rain_fx.material_override = mat(Color("cfe8ff"), true)
	rain_fx.amount = 260
	rain_fx.lifetime = 0.8
	rain_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain_fx.emission_box_extents = Vector3(13, 1, 13)
	rain_fx.position = Vector3(-2, 10, -7)
	rain_fx.direction = Vector3(0.22, -1, 0.08)
	rain_fx.spread = 2.0
	rain_fx.initial_velocity_min = 22.0
	rain_fx.initial_velocity_max = 27.0
	rain_fx.gravity = Vector3.ZERO
	rain_fx.emitting = false
	wind_fx.add_child(rain_fx)


func gen_path() -> void:
	# Forward runs alternate with short sideways runs, so the path winds without
	# crossing itself. Each run also has a height profile: flat, a flight of
	# stairs up or down, a rolling hump, one tall ledge to climb or one big drop
	# to leap. On top of that every slab sits slightly higher or lower than its
	# neighbours, like worn stepping stones.
	path.clear()
	dirs.clear()
	yaws.clear()
	base_y.clear()
	var at := Vector3(0, 0.25, 0)
	var sideways := false
	var i := 0
	while i <= END:
		var fwd: Vector2i = style.fwd
		var sd: Vector2i = style.side
		var n := rng.randi_range(sd.x, sd.y) if sideways else rng.randi_range(fwd.x, fwd.y)
		var d := Vector3(0, 0, -1)
		if sideways:
			var sgn := -signf(at.x) if absf(at.x) > 5.0 else (1.0 if rng.randf() < 0.5 else -1.0)
			d = Vector3(sgn, 0, 0)
		var prof := "flat"
		if i > 5 and i < END - 4:
			if sideways:
				prof = ["flat", "rolling", "stairs_up"][rng.randi_range(0, 2)]
			else:
				prof = style.prof[rng.randi_range(0, style.prof.size() - 1)]
		if at.y < -1.0 and (prof == "stairs_down" or prof == "drop"):
			prof = "stairs_up"  # never sink far below the start
		var big_at := rng.randi_range(1, maxi(1, n - 2))
		for k in n:
			if i > END:
				break
			var level := i < 5 or i >= END - 3  # start and gate stay flat
			path.append(at + Vector3(0, 0.0 if level else rng.randf_range(-0.1, 0.1), 0))
			base_y.append(at.y)
			dirs.append(d)
			yaws.append(atan2(-d.x, -d.z))
			var rise := 0.0
			match prof:
				"stairs_up":
					rise = 0.55
				"stairs_down":
					rise = -0.45
				"rolling":
					rise = sin(float(k) / n * TAU) * 0.55
				"ledge":
					rise = 1.7 if k == big_at else 0.0
				"drop":
					rise = -1.9 if k == big_at else 0.0
			if level:
				rise = 0.0
			at += d * GAP + Vector3(0, rise, 0)
			i += 1
		sideways = not sideways


func path_dist(at: Vector3) -> float:
	var best := 1e9
	for q in path:
		best = minf(best, Vector2(q.x - at.x, q.z - at.z).length())
	return best


func gen_board() -> void:
	# Traps (spikes, cracked slab, cobra, tiger) always have at least two
	# harmless slabs between them, so a bad stretch can never box a runner in.
	# A cobra's throw lands on a plain slab with no trap beside it.
	kinds.clear()
	rope_to.clear()
	snake_to.clear()
	for i in END + 1:
		kinds.append("")
	var reserved := {}
	var last_trap := -9
	for i in range(6, END - 1):
		if reserved.has(i):
			continue
		var clear := i - last_trap >= 3
		var r := rng.randf()
		if r < 0.07:
			if clear:
				kinds[i] = "spike"
		elif r < 0.13:
			if clear:
				kinds[i] = "crumble"
		elif r < 0.19:
			var d := i - rng.randi_range(4, 7)
			if clear and i > 12 and kinds[d] in ["", "coin"] and not kinds[d - 1] in HARMFUL and not kinds[d + 1] in HARMFUL:
				kinds[i] = "snake"
				snake_to[i] = d
				kinds[d] = ""
		elif r < 0.28:
			var d := i + rng.randi_range(5, 9)
			if d < END and not reserved.has(d):
				kinds[i] = "rope"
				rope_to[i] = d
				reserved[d] = true
		elif r < 0.36:
			kinds[i] = "mystery"
		elif r < 0.40:
			if clear and i > 12:
				kinds[i] = "tiger"
		elif r < 0.60:
			kinds[i] = "coin"
		elif r < 0.64:
			kinds[i] = "diamond"
		if kinds[i] in HARMFUL:
			last_trap = i


func build_world() -> void:
	if world:
		world.queue_free()
	world = Node3D.new()
	view.add_child(world)
	slabs.clear()
	pickups.clear()
	rescues.clear()
	pin_at.clear()
	pin_bo = float(bo)
	reveals.clear()
	hurdles.clear()
	snakes.clear()
	tigers.clear()
	spikes.clear()
	players.clear()
	finished.clear()

	for i in END + 1:
		slabs.append(make_slab(i, kinds[i]))
	_build_ropes()
	_build_cave()
	_build_scenery()

	for k in bot_count + 1:
		var r: Dictionary = ROSTER[k]
		var p := {"name": r.name, "color": r.color, "off": r.off, "bot": k > 0,
			"pos": 0, "out": false, "done": false, "danger": false, "skip": 0, "hearts": 3, "coins": 0, "revives": 2, "shield": false, "wounded": 0, "banana": 0, "hit": {}}
		p["a"] = make_actor(r.color, "YOU" if k == 0 else "")
		p.a.position = spot(p, 0)
		players.append(p)
	focus_p = players[0]
	cam_base = path[0]
	cam_dir = Vector3(0, 0, -1)
	cam_yaw = PI

	boulder = Node3D.new()
	boulder.position = slab_pos(bo) + Vector3(0, 1.25, 0)
	world.add_child(boulder)
	ball = Node3D.new()
	boulder.add_child(ball)
	for x in range(-3, 4):
		for y in range(-3, 4):
			for z in range(-3, 4):
				var d := Vector3(x, y, z).length()
				if d <= 3.4 and d >= 2.3:
					box(ball, Vector3.ONE * 0.36, Vector3(x, y, z) * 0.36, shade(Color("6f6a60")))
	ball_last = boulder.position

	marker = Node3D.new()
	world.add_child(marker)
	for k in 3:  # a down-pointing arrow head, widest at the top
		box(marker, Vector3(0.5 - k * 0.17, 0.14, 0.16), Vector3(0, 0.28 - k * 0.14, 0), GOLD).material_override = mat(GOLD, true)
	box(marker, Vector3(0.16, 0.3, 0.16), Vector3(0, 0.5, 0), GOLD).material_override = mat(GOLD, true)

	# birds wheel in slow circles above the canopy
	circlers.clear()
	var tints := [Color("f4f4f0"), Color("3fbf5a"), Color("3f9fe0"), Color("e2463a"), Color("f2d24a")]
	for k in 5:
		var c := Node3D.new()
		c.position = path[rng.randi_range(5, END - 5)] + Vector3(rng.randf_range(-10, 10), rng.randf_range(4, 9), rng.randf_range(-10, 10))
		c.set_meta("w", rng.randf_range(0.5, 0.9))
		world.add_child(c)
		var r := rng.randf_range(4.0, 8.0)
		var tint: Color = tints[rng.randi_range(0, 4)]
		for j in rng.randi_range(2, 4):
			var bird: Node3D = Animals.build("bird", self, tint)
			var ang := j * 0.7
			bird.position = Vector3(cos(ang) * r, sin(j * 1.7) * 0.6, sin(ang) * r)
			bird.rotation.y = -ang
			bird.scale = Vector3.ONE * 1.3
			c.add_child(bird)
		circlers.append(c)


func make_slab(i: int, kind: String) -> Node3D:
	var root := Node3D.new()
	root.position = path[i] - Vector3(0, 0.25, 0)
	root.rotation.y = yaws[i]
	world.add_child(root)
	var base := STONE
	match kind:
		"crumble": base = STONE.darkened(0.07)  # looks almost like any other slab
		"rope": base = Color("9fd98a")  # green: a way forward
		"snake": base = SNAKE
		"mystery": base = MYSTERY
	if i == END:
		base = GOLD
	var blocks: Array[MeshInstance3D] = []
	for bx in [-0.66, 0.0, 0.66]:
		for bz in [-0.66, 0.0, 0.66]:
			var dip := rng.randf_range(0.0, 0.08)
			blocks.append(box(root, Vector3(0.66, 0.5, 0.66), Vector3(bx, -dip, bz), shade(base)))
	root.set_meta("blocks", blocks)
	# pillar: the top is loose blocks (they can collapse); below that one long shaft
	var shaft: Array[MeshInstance3D] = []
	for k in 5:
		shaft.append(box(root, Vector3(0.95, 1.2, 0.95), Vector3(0, -0.85 - k * 1.2, 0), shade(DARK.lightened(0.14))))
	root.set_meta("shaft", shaft)
	box(root, Vector3(0.9, 34, 0.9), Vector3(0, -23.25, 0), shade(DARK))

	if i % 5 == 0 and i > 0:  # torch posts: also the checkpoints players are reborn at
		for side in [-1, 1]:
			box(root, Vector3(0.16, 1.1, 0.16), Vector3(side * 1.08, 0.8, 0), Color("4a3b2a"))
			box(root, Vector3.ONE * 0.26, Vector3(side * 1.08, 1.45, 0), Color("ff9a2e")).material_override = mat(Color("ff9a2e"), true)
			box(root, Vector3.ONE * 0.14, Vector3(side * 1.08, 1.68, 0), Color("ffe066")).material_override = mat(Color("ffe066"), true)
			flame(root, Vector3(side * 1.08, 1.7, 0))

	if i % 12 == 6 and i < END - 3:  # a ruined gateway arch, hung with vines
		var stone := Color("b9a67c")
		for side in [-1, 1]:
			box(root, Vector3(0.55, 7.0, 0.55), Vector3(side * 2.2, 3.5, 0), shade(stone))
			box(root, Vector3(0.75, 0.4, 0.75), Vector3(side * 2.2, 0.45, 0), shade(stone.darkened(0.1)))
			box(root, Vector3(0.14, rng.randf_range(1.5, 3.5), 0.14), Vector3(side * rng.randf_range(0.3, 1.3), 5.6, 0.2), shade(MOSS))
		box(root, Vector3(5.6, 0.7, 0.75), Vector3(0, 7.2, 0), shade(stone))
		box(root, Vector3(4.0, 0.5, 0.6), Vector3(0, 7.8, 0), shade(stone.lightened(0.08)))
		box(root, Vector3(0.5, 0.5, 0.5), Vector3(0, 8.3, 0), GOLD).material_override = mat(GOLD, true)

	var num := Label3D.new()
	num.text = str(i)
	num.font_size = 96
	num.pixel_size = 0.011
	num.font = font
	num.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	num.modulate = Color("2a2118")
	num.rotation_degrees.x = -90
	num.position = Vector3(0, 0.27, 0)  # centred on the tile
	root.add_child(num)

	if kind == "" and i > 5 and i < END - 1 and i % 5 != 0 and rng.randf() < 0.24:
		# parkour hurdle on the near edge: runners vault or flip the low ones and slide under the beam
		var h: String = ["log", "block", "beam"][rng.randi_range(0, 2)]
		hurdles[i] = h
		match h:
			"log":
				box(root, Vector3(2.1, 0.42, 0.42), Vector3(0, 0.46, 0.8), shade(Color("6b4a2c")))
				box(root, Vector3(0.1, 0.44, 0.44), Vector3(1.0, 0.46, 0.8), Color("c9a26b"))
				box(root, Vector3(0.1, 0.44, 0.44), Vector3(-1.0, 0.46, 0.8), Color("c9a26b"))
			"block":
				box(root, Vector3(1.9, 0.6, 0.45), Vector3(0, 0.55, 0.8), shade(Color("9a8f72")))
				box(root, Vector3(0.7, 0.14, 0.5), Vector3(0.3, 0.9, 0.8), shade(MOSS))
			"beam":
				for side in [-1, 1]:
					box(root, Vector3(0.18, 1.7, 0.18), Vector3(side * 0.95, 1.1, 0.8), Color("6b4a2c"))
				box(root, Vector3(2.2, 0.2, 0.2), Vector3(0, 1.75, 0.8), Color("8a6a44"))

	match kind:
		"spike":
			var sp := Node3D.new()
			root.add_child(sp)
			for sx in [-0.6, 0.0, 0.6]:
				for sz in [-0.5, 0.0]:
					box(sp, Vector3(0.14, 0.7, 0.14), Vector3(sx, 0.6, sz), Color("d9dde2"))
					box(sp, Vector3(0.22, 0.2, 0.22), Vector3(sx, 0.32, sz), Color("7d848c"))
			spikes[i] = sp
		"crumble":
			root.rotation.z = 0.06
			for c in 3:
				box(root, Vector3(rng.randf_range(0.5, 1.2), 0.04, 0.08), Vector3(rng.randf_range(-0.4, 0.4), 0.27, rng.randf_range(-0.7, 0.3)), Color("2a1c14")).rotation.y = rng.randf_range(-0.8, 0.8)
		"snake":
			var cobra: Node3D = Animals.build("cobra", self)
			root.add_child(cobra)
			snakes[i] = {"node": cobra, "was": false}
		"tiger":
			# claw marks and old bones warn that a tiger hunts here
			for k in 3:
				box(root, Vector3(0.07, 0.03, 1.1), Vector3(-0.3 + k * 0.3, 0.27, -0.1), Color("2a1c14")).rotation.y = 0.35
			box(root, Vector3(0.5, 0.08, 0.1), Vector3(0.55, 0.3, 0.6), Color("f1ecdc")).rotation.y = 0.7
			box(root, Vector3(0.4, 0.08, 0.1), Vector3(-0.6, 0.3, 0.5), Color("f1ecdc")).rotation.y = -0.5
			box(root, Vector3(0.22, 0.2, 0.22), Vector3(0.7, 0.36, -0.6), Color("f1ecdc"))
			for k in 4:  # big paw prints crossing the slab
				var px := -0.55 + k * 0.36
				var pz := 0.55 if k % 2 == 0 else 0.2
				box(root, Vector3(0.2, 0.03, 0.2), Vector3(px, 0.27, pz), Color("3a2414"))
				for tz in [-0.1, 0.0, 0.1]:
					box(root, Vector3(0.07, 0.03, 0.07), Vector3(px + tz, 0.27, pz - 0.17), Color("3a2414"))
		"rope":
			_post(root)
			var green := Color("52d273")
			box(root, Vector3.ONE * 0.3, Vector3(-1.12, 4.4, 0), green).material_override = mat(green, true)
			for k in 3:  # a bold arrow on the slab, pointing onward
				box(root, Vector3(1.2 - k * 0.42, 0.05, 0.2), Vector3(0, 0.27, -0.15 - k * 0.24), Color("1f9e4a")).material_override = mat(Color("1f9e4a"), true)
			box(root, Vector3(0.26, 0.05, 0.6), Vector3(0, 0.27, 0.3), Color("1f9e4a")).material_override = mat(Color("1f9e4a"), true)
		"mystery":
			var q := Label3D.new()
			q.text = "?"
			q.font_size = 200
			q.outline_size = 40
			q.pixel_size = 0.008
			q.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			q.font = font
			q.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			q.modulate = Color("f1d6ff")
			q.position = Vector3(0, 1.6, -0.2)
			root.add_child(q)
			q.visible = ui_tex("s_mystery") == null  # the painted sign replaces it
		"coin":
			var coin := box(root, Vector3(0.44, 0.44, 0.1), Vector3(0, 1.15, 0), GOLD)
			coin.material_override = mat(GOLD, true)
			pickups[i] = coin
		"diamond":
			var gem := box(root, Vector3.ONE * 0.36, Vector3(0, 1.2, 0), Color("36d6e8"))
			gem.material_override = mat(Color("36d6e8"), true)
			gem.rotation = Vector3(0.6, 0, 0.6)
			pickups[i] = gem

	# Every special slab is ringed in a meaning colour (red danger, green help,
	# purple mystery) and carries a floating picture sign.
	# Rims, signs and captions start hidden and appear only when a runner comes
	# close, so the road far ahead keeps its surprises but what is next is clear.
	var sign_id: String = {"snake": "s_snake", "rope": "s_rope", "crumble": "s_crumble", "spike": "s_spike", "mystery": "s_mystery", "tiger": "s_tiger"}.get(kind, "")
	if sign_id != "":
		var rc: Color = {"rope": Color("3fe07a"), "mystery": Color("b06aff"), "crumble": Color("ff9a2e")}.get(kind, Color("ff4a3a"))
		var hidden: Array[Node3D] = []
		for e in [-1.0, 1.0]:
			var r1 := box(root, Vector3(2.06, 0.08, 0.12), Vector3(0, 0.28, e * 0.97), rc)
			var r2 := box(root, Vector3(0.12, 0.08, 2.06), Vector3(e * 0.97, 0.28, 0), rc)
			r1.material_override = mat(rc, true)
			r2.material_override = mat(rc, true)
			hidden.append(r1)
			hidden.append(r2)
		var sign_y := 2.5  # just above head height, over its own slab
		var board: Sprite3D = null
		var st := ui_tex(sign_id)
		if st:
			board = Sprite3D.new()
			board.texture = st
			board.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			board.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			board.pixel_size = 0.58 / st.get_width()
			board.position = Vector3(0, sign_y, 0)
			root.add_child(board)
			hidden.append(board)
		# a caption under the sign says what the slab does
		var words := ""
		match kind:
			"rope": words = "ROPE +%d" % (rope_to[i] - i)
			"snake": words = "COBRA -%d" % (i - snake_to[i])
			"tiger": words = "TIGER!"
			"spike": words = "JUMP!"
			"crumble": words = "CRACKED"
			"mystery": words = "MYSTERY"
		var cap := Label3D.new()
		cap.text = words
		cap.font = ui_font
		cap.font_size = 48
		cap.outline_size = 16
		cap.pixel_size = 0.0075
		cap.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		cap.no_depth_test = true
		cap.modulate = rc.lightened(0.35)
		cap.position = Vector3(0, sign_y + 0.55, 0)
		root.add_child(cap)
		hidden.append(cap)
		if kind == "tiger":  # eyes watching from a bush beside the path
			var lurk := Node3D.new()
			lurk.position = Vector3(2.3, -0.2, 0.1)
			root.add_child(lurk)
			box(lurk, Vector3(1.5, 1.2, 1.3), Vector3(0, 0.3, 0), Color("1f5a2c"))
			box(lurk, Vector3(1.0, 0.7, 1.0), Vector3(0.1, 1.1, 0), Color("2a7036"))
			box(lurk, Vector3(0.7, 0.6, 0.1), Vector3(-0.72, 0.75, 0), Color("0a120c"))  # dark hollow
			for ez in [-0.17, 0.17]:
				box(lurk, Vector3(0.06, 0.1, 0.13), Vector3(-0.8, 0.82, ez), Color("ffe23a")).material_override = mat(Color("ffe23a"), true)
			hidden.append(lurk)
		for n in hidden:
			n.visible = false
		reveals[i] = {"nodes": hidden, "board": board, "radius": 2 if kind == "crumble" else 3, "shown": false, "kind": kind, "cap": cap}
	return root


func _build_cave() -> void:
	# The race begins at a temple cave in the mountainside, five slabs behind
	# slab 0, joined to it by a short causeway. The boulder sleeps inside.
	var rock := Color("6b6f66")
	var trim := Color("b9a67c")
	var c := Node3D.new()
	c.position = path[0] - Vector3(0, 0.25, 0)
	world.add_child(c)
	for k in range(1, 9):
		box(c, Vector3(2.0, 0.5, GAP), Vector3(0, 0, GAP * k), shade(STONE))
		box(c, Vector3(0.9, 34, 0.9), Vector3(0, -17.25, GAP * k), shade(DARK))
	var mz := GAP * 5.0  # the mouth
	for side in [-1, 1]:
		box(c, Vector3(5.4, 11, 10), Vector3(side * 4.5, 5.0, mz + 5.0), shade(rock))
		box(c, Vector3(0.75, 4.7, 0.75), Vector3(side * 1.78, 2.55, mz - 0.15), shade(trim))
		box(c, Vector3(0.2, 4.7, 10), Vector3(side * 1.82, 2.55, mz + 5.0), Color("0c0a08"))
		box(c, Vector3(0.18, 1.4, 0.18), Vector3(side * 2.7, 1.9, mz - 0.6), Color("4a3b2a"))
		box(c, Vector3.ONE * 0.3, Vector3(side * 2.7, 2.75, mz - 0.6), Color("ff9a2e")).material_override = mat(Color("ff9a2e"), true)
		flame(c, Vector3(side * 2.7, 3.0, mz - 0.6))
		box(c, Vector3(0.36, 0.3, 0.1), Vector3(side * 0.52, 6.95, mz - 0.42), GOLD).material_override = mat(GOLD, true)  # glowing eyes
		box(c, Vector3(0.16, rng.randf_range(1.5, 3.5), 0.16), Vector3(side * rng.randf_range(2.4, 5.5), 8.5, mz - 0.1), shade(MOSS))
	box(c, Vector3(14.4, 6.0, 10), Vector3(0, 7.9, mz + 5.0), shade(rock))
	box(c, Vector3(4.6, 0.7, 0.85), Vector3(0, 5.05, mz - 0.15), shade(trim))
	box(c, Vector3(2.4, 2.0, 0.5), Vector3(0, 6.7, mz - 0.15), shade(Color("9a8f72")))  # carved face
	box(c, Vector3(0.9, 0.3, 0.1), Vector3(0, 6.15, mz - 0.42), Color("2a2118"))
	box(c, Vector3(3.5, 4.7, 0.3), Vector3(0, 2.55, mz + 9.8), Color("0c0a08"))
	box(c, Vector3(3.5, 0.2, 10), Vector3(0, 4.95, mz + 5.0), Color("0c0a08"))
	box(c, Vector3(14.8, 0.6, 10.4), Vector3(0, 11.1, mz + 5.0), shade(MOSS))
	# The cave is the face of a cliff, not a floating block: rock runs down to
	# the valley floor beneath it, back into the mountain behind it, and out to
	# both sides in stepped shoulders. A ledge juts under the doorway.
	box(c, Vector3(15.0, 40, 19), Vector3(0, -20.4, mz + 9.5), shade(rock))
	box(c, Vector3(15.0, 13, 9.5), Vector3(0, 6.0, mz + 14.6), shade(rock))
	box(c, Vector3(5.2, 1.0, 2.2), Vector3(0, -0.75, mz - 0.9), shade(rock.lightened(0.08)))
	for side in [-1, 1]:
		box(c, Vector3(4.5, 46, 15), Vector3(side * 9.4, -17.5, mz + 9.0), shade(rock.darkened(0.06)))
		box(c, Vector3(3.6, 38, 11), Vector3(side * 13.0, -22.5, mz + 10.0), shade(rock.darkened(0.12)))
		box(c, Vector3(4.6, 0.6, 15.2), Vector3(side * 9.4, 5.7, mz + 9.0), shade(MOSS))
		for v in 3:  # vines down the cliff face
			box(c, Vector3(0.18, rng.randf_range(3, 9), 0.18), Vector3(side * rng.randf_range(2.6, 11.0), -3.0 - v * 2.0, mz - 0.15), shade(MOSS))
	for k in 5:  # rubble and ledges on the face below the door
		box(c, Vector3(rng.randf_range(1.5, 4.0), rng.randf_range(0.6, 1.4), 1.2), Vector3(rng.randf_range(-5, 5), -3.0 - k * 3.2, mz - 0.4), shade(rock.lightened(0.05)))


func count(text: String, c: Color) -> void:
	# giant centre-screen count: slams in big, settles, fades
	lbl_count.text = text
	lbl_count.add_theme_color_override("font_color", c)
	lbl_count.modulate.a = 1.0
	lbl_count.scale = Vector2(2.2, 2.2)
	var tw := lbl_count.create_tween()
	tw.tween_property(lbl_count, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.3)
	tw.tween_property(lbl_count, "modulate:a", 0.0, 0.22)


func apply_safe_area() -> void:
	# Fit the UI to the real screen: match the 2D viewport to the window's
	# shape, and inset the HUD by the device's unsafe edges (notch, punch-hole
	# camera, rounded corners, home-gesture bar). Runs again if the window changes.
	var vis := get_viewport().get_visible_rect().size
	ui_layer.size_2d_override = Vector2i(vis)
	var inset := [0.0, 0.0, 0.0, 0.0]  # left, top, right, bottom, in UI units
	if OS.has_feature("mobile"):
		var screen := Vector2(DisplayServer.screen_get_size())
		var area := DisplayServer.get_display_safe_area()
		if screen.x > 0.0 and screen.y > 0.0 and area.size.x > 0:
			var k := vis.y / screen.y
			inset = [area.position.x * k, area.position.y * k, (screen.x - area.end.x) * k, (screen.y - area.end.y) * k]
	if OS.has_environment("VAULT_SAFE"):  # dev: "top,bottom" to preview a notched phone on desktop
		var parts := OS.get_environment("VAULT_SAFE").split(",")
		inset = [0.0, float(parts[0]), 0.0, float(parts[1]) if parts.size() > 1 else 0.0]
	# On a wide window (desktop browser, tablet on its side) the world fills the
	# whole view, while menus and HUD keep to a centred portrait column.
	var column := vis.y * 0.5625
	if vis.x > column * 1.1:
		var side := (vis.x - column) / 2.0
		inset[0] = maxf(inset[0], side)
		inset[2] = maxf(inset[2], side)
	safe.offset_left = inset[0]
	safe.offset_top = inset[1]
	safe.offset_right = -inset[2]
	safe.offset_bottom = -inset[3]
	lbl_big.pivot_offset = Vector2(vis.x / 2.0, 50)
	lbl_count.pivot_offset = vis / 2.0
	reward_rays.position.x = vis.x / 2.0


func toggle_pause() -> void:
	var on := not get_tree().paused
	get_tree().paused = on
	pause_panel.visible = on
	sfx.play("step")


func restart_race() -> void:
	# a clean slate: reload the scene and go straight into a new race
	dead = true
	boot_bots = bot_count
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene.call_deferred()  # after this tap has finished being handled


func exit_to_lobby() -> void:
	dead = true
	boot_bots = 0
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene.call_deferred()  # after this tap has finished being handled


func _draw_pause(b: Control) -> void:
	var col := Color("fff3c4")
	var w := b.size.x
	b.draw_rect(Rect2(w * 0.3, w * 0.28, w * 0.14, w * 0.44), col)
	b.draw_rect(Rect2(w * 0.56, w * 0.28, w * 0.14, w * 0.44), col)


func letterbox(on: bool) -> void:
	var h := 130.0 if on else 0.0
	bars[0].create_tween().tween_property(bars[0], "offset_bottom", h, 0.5).set_trans(Tween.TRANS_SINE)
	bars[1].create_tween().tween_property(bars[1], "offset_top", -h, 0.5).set_trans(Tween.TRANS_SINE)


func _cine_fly(t: float) -> void:
	# Establishing shot: a steady crane glide down the valley from the temple
	# gate to the start. The camera keeps to one straight line, high and to one
	# side, and only pans to follow a point travelling along the path, so the
	# path's corners never jerk it about.
	var f := lerpf(float(END) - 1.5, 1.5, t)
	var i := int(f)
	var at := path[i].lerp(path[i + 1], f - i)
	var a := path[END]
	var b := path[0]
	var line := a.lerp(b, t)  # straight from gate to start
	cine_pos = Vector3(line.x + 11.0, at.y + 11.0, line.z - 9.0)
	cine_look = Vector3(lerpf(line.x, at.x, 0.5), at.y + 1.0, line.z + 5.0)


func _cine_push(t: float, c: Vector3) -> void:
	# slow push in on the cave mouth
	cine_pos = (c + Vector3(0, 3.6, -14.0)).lerp(c + Vector3(0, 2.3, -6.2), t)
	cine_look = c + Vector3(0, 1.6, GAP * 5.0)


func intro() -> void:
	# Opening scene, letterboxed, HUD away. 1) The camera glides from the temple
	# gate back down the path, with the map's name. 2) It pushes in on the cave
	# as the ground rumbles. 3) The runners come out one at a time, named, each
	# with their own move, in light slow motion. 4) The bars open, the camera
	# sweeps round behind the pack, and the countdown starts. A tap skips it.
	in_cine = true
	skip_intro = false
	var c := path[0]
	var mouth := c + Vector3(0, 0, GAP * 5.0)
	for n in hud_nodes:
		if n != lbl_big:
			n.visible = false
	letterbox(true)
	for p in players:
		p.a.visible = false
		p.a.rotation = Vector3(0, yaws[0], 0)
	say("")

	_cine_fly(0.0)
	cam.position = cine_pos
	cine_look_now = cine_look
	cine_smooth = 2.5
	announce(style.name.to_upper(), GOLD)
	var fly := create_tween()
	fly.tween_method(_cine_fly, 0.0, 1.0, 4.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	while fly.is_running() and not skip_intro:
		await frame()
	fly.kill()
	cine_smooth = 0.0

	if not skip_intro:
		sfx.play("boulder", -6.0)
		shake(0.35)
		cine_smooth = 3.0  # ease out of the glide into the push-in, no cut
		var push := create_tween()
		push.tween_method(_cine_push.bind(c), 0.0, 1.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		while push.is_running() and not skip_intro:
			await frame()
		push.kill()
	cine_smooth = 0.0
	_cine_orbit(0.0, c)
	cine_look = mouth + Vector3(0, 1.6, 0)
	cine_look_now = cine_look

	var moves := ["flip", "slide", "spin", "somersault", "roll", "long"]
	for k in players.size():
		var p := players[k]
		var root: Node3D = p.a
		var col: Color = p.color
		root.visible = true
		if skip_intro:
			root.position = spot(p, 0)
			continue
		announce("YOU" if k == 0 else p.name, col.lightened(0.35))
		sfx.play("good", -8.0, 0.9 + k * 0.08)
		cine_target = root
		# sprint out of the dark to one slab short of the start
		root.position = mouth + Vector3(p.off.x, 0, 2.6)
		root.run = true
		var take_off: Vector3 = spot(p, 0) + Vector3(0, 0, GAP * 1.4)
		var tw := root.create_tween()
		tw.tween_property(root, "position", take_off, 1.0)
		await tw.finished
		root.run = false
		# then their own move onto the start slab, slowed so it can be enjoyed
		var style_k: String = moves[k % moves.size()]
		root.pose = {"flip": "tuck", "slide": "slide", "roll": "tuck", "spin": "cheer", "long": "", "somersault": "tuck"}[style_k]
		root.air = style_k == "long"
		sfx.play("jump", -8.0)
		slow_to = 0.55
		var mv := create_tween()
		mv.tween_method(_parkour.bind(root, take_off, spot(p, 0), style_k, yaws[0]), 0.0, 1.0, 0.7 if style_k == "somersault" else 0.5)
		await mv.finished
		slow_to = 1.0
		root.air = false
		root.rotation = Vector3(0, yaws[0], 0)
		root.position = spot(p, 0)
		squash(root)
		sfx.play("land", -5.0)
		burst(root.position + Vector3(0, 0.3, 0), col, 12, 3.5)
		root.pose = "cheer"
		await wait(0.3)
		root.pose = ""
	cine_target = null
	slow_to = 1.0
	letterbox(false)
	if not skip_intro:
		await wait(0.2)
		sfx.play("boulder", -3.0)
		shake(0.6)
		var tw2 := create_tween()
		tw2.tween_method(_cine_orbit.bind(c), 0.0, 1.0, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tw2.finished
	cam_base = c
	cam_yaw = PI
	in_cine = false
	for n in hud_nodes:
		n.visible = true
	lbl_hint.visible = false
	turn_bar.visible = false
	refresh_ui()
	# 3, 2, 1, GO
	if not skip_intro:
		for n in ["3", "2", "1"]:
			count(n, Color("fff3c4"))
			sfx.play("step", 2.0, 1.7)
			await wait(0.8)
	count("GO!", GOLD)
	sfx.play("good")
	await wait(0.5)


func _cine_orbit(t: float, c: Vector3) -> void:
	# t 0: dead ahead of the start on the path's centre line, facing the runners.
	# t 1: the normal spot behind them. It swings round one side in between.
	var a := lerpf(0.0, PI, t)
	var r := lerpf(6.2, 7.4, t)
	cine_pos = c + Vector3(sin(a) * r, lerpf(2.3, 6.6, t), -cos(a) * r)
	cine_look = (c + Vector3(0, 1.1, 0)).lerp(c + Vector3(0, 0.6, -5.5), t)


func _post(slab: Node3D) -> void:
	box(slab, Vector3(0.24, 4.1, 0.24), Vector3(-1.12, 2.3, 0), Color("6b4a2c"))
	box(slab, Vector3(0.5, 0.16, 0.5), Vector3(-1.12, 4.15, 0), Color("4a3320"))


func rope_end(i: int) -> Vector3:
	return path[i] + Vector3(-1.12, 3.9, 0).rotated(Vector3.UP, yaws[i])


func _build_ropes() -> void:
	# A real hanging rope links each rope slab to where it leads.
	ropes.clear()
	var rope_mat := mat(Color("d8b25a"))
	for i in rope_to:
		var d: int = rope_to[i]
		_post(slabs[d])
		# the far end is marked too: green cap on its post and green corners on the slab
		var green := Color("52d273")
		box(slabs[d], Vector3.ONE * 0.3, Vector3(-1.12, 4.4, 0), green).material_override = mat(green, true)
		for cx in [-0.85, 0.85]:
			for cz in [-0.85, 0.85]:
				box(slabs[d], Vector3(0.3, 0.06, 0.3), Vector3(cx, 0.28, cz), green).material_override = mat(green, true)
		var a := rope_end(i)
		var b := rope_end(d)
		var dist := a.distance_to(b)
		var n := clampi(int(dist / 1.1), 8, 22)
		ropes[i] = {"s": Strand.new(world, n, dist * 1.07 / n, Vector2(0.1, 0.1), rope_mat, a, (b - a).normalized()), "a": a, "b": b}


func _ride(f: float, s: Strand, root: Node3D) -> void:
	# Rider hangs from the rope by the hands; their weight makes it sag.
	s.weigh(f, 0.035)
	var at := s.point_at(f)
	var ahead := s.point_at(minf(1.0, f + 0.05)) - at
	root.position = at - Vector3(0, 1.75, 0)
	if Vector2(ahead.x, ahead.z).length() > 0.01:
		root.rotation.y = atan2(-ahead.x, -ahead.z)


func _build_scenery() -> void:
	nature = Nature.new()
	world.add_child(nature)
	nature.build(self)

	var gate := Node3D.new()
	gate.position = path[END] - Vector3(0, 0.25, 0) + dirs[END] * 3.2
	gate.rotation.y = yaws[END]
	world.add_child(gate)
	box(gate, Vector3(6, 0.5, 4), Vector3(0, 0, 0), shade(STONE))
	for side in [-1, 1]:
		for k in 6:
			box(gate, Vector3.ONE * 1.2, Vector3(side * 2.4, 0.85 + k * 1.2, -1.2), shade(Color("a58f4f")))
	box(gate, Vector3(6.6, 1.2, 1.2), Vector3(0, 8.05, -1.2), GOLD).material_override = mat(GOLD, true)
	box(gate, Vector3(1.2, 0.7, 0.8), Vector3(0, 0.6, -0.4), Color("6b4424"))
	box(gate, Vector3(1.26, 0.2, 0.86), Vector3(0, 0.95, -0.4), GOLD)
	for c in 14:
		box(gate, Vector3.ONE * 0.2, Vector3(rng.randf_range(-1.6, 1.6), 0.35, rng.randf_range(-0.9, 1.2)), shade(GOLD))


func make_actor(c: Color, tag := "") -> Node3D:
	var a: Node3D = Actor.new()
	world.add_child(a)
	a.setup(self, c, tag)
	return a


# ---------------------------------------------------------------- ui

func _round(c: Color, radius := 18, border := 0, bc := Color("2a2118")) -> StyleBoxFlat:
	# rounded plaque with an optional border and a hard drop shadow
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.corner_detail = 8
	s.set_border_width_all(border)
	s.border_color = bc
	s.set_content_margin_all(12)
	if border > 0:
		s.shadow_color = Color(0, 0, 0, 0.45)
		s.shadow_size = 2
		s.shadow_offset = Vector2(0, 7)
	return s


func ui_tex(id: String) -> Texture2D:
	if not tex_cache.has(id):
		var path := "res://ui/%s.png" % id
		tex_cache[id] = load(path) if ResourceLoader.exists(path) else null
	return tex_cache[id]


func _btn_style(c: Color, pressed: bool) -> StyleBox:
	# Painted button art, picked by the colour asked for (orange, green, wood,
	# grey); the ends stay crisp while the middle stretches. Flat fallback if absent.
	var kind := "wood"
	if c.s < 0.15:
		kind = "grey"
	elif c.h > 0.22 and c.h < 0.45:
		kind = "green"
	elif c.h < 0.13 and c.v > 0.75:
		kind = "orange"
	var t := ui_tex("btn_" + kind)
	if t == null:
		var f := _round(c, 22, 5, Color("ffd76a"))
		f.border_width_bottom = 7 if pressed else 16
		f.set_content_margin_all(16)
		return f
	var s := StyleBoxTexture.new()
	s.texture = t
	var h := float(t.get_height())
	s.texture_margin_left = h * 0.55
	s.texture_margin_right = h * 0.55
	s.texture_margin_top = h * 0.34
	s.texture_margin_bottom = h * 0.4
	s.set_content_margin_all(18)
	s.content_margin_bottom = 26
	if pressed:
		s.modulate_color = Color(0.78, 0.78, 0.78)
		s.content_margin_top = 26
	return s


func _tablet() -> StyleBox:
	# the carved stone panel menus and results sit on
	var t := ui_tex("panel")
	if t == null:
		var f := _round(Color(0.13, 0.09, 0.06, 0.92), 30, 6, Color("f2c14e"))
		f.set_content_margin_all(30)
		return f
	var s := StyleBoxTexture.new()
	s.texture = t
	var m := float(t.get_width()) * 0.2
	s.texture_margin_left = m
	s.texture_margin_right = m
	s.texture_margin_top = m * 1.25  # keeps the vines on the top corners whole
	s.texture_margin_bottom = m
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT  # stone blocks repeat, not smear
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	s.set_content_margin_all(m * 0.8)
	s.content_margin_top = m * 0.95
	return s


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", ui_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color("2a2118"))
	l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_ui() -> void:
	var uc := SubViewportContainer.new()
	uc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	uc.stretch = true
	uc.stretch_shrink = 1  # menus and HUD stay crisp; only the 3D world is pixelated
	uc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	uc.process_mode = Node.PROCESS_MODE_ALWAYS  # menus must still answer taps while the game is paused
	add_child(uc)
	var layer := SubViewport.new()
	layer.transparent_bg = true
	layer.size_2d_override = Vector2i(get_viewport().get_visible_rect().size)
	layer.size_2d_override_stretch = true
	layer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	uc.add_child(layer)
	ui_layer = layer
	# Everything a player must read or tap goes inside "safe", which is inset
	# from the screen edges by the phone's notch / status area and home bar.
	# Full-bleed things (dimmers, flashes, letterbox) stay on the layer itself.
	safe = Control.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(safe)

	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 14
	top.offset_right = -14
	top.offset_top = 30
	top.offset_bottom = 300
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(top)

	# one carved plaque per player: face, slab, lives, coins
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(row)
	for k in ROSTER.size():
		var chip := Control.new()
		chip.custom_minimum_size = Vector2(0, 100)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.draw.connect(_draw_chip.bind(k))
		row.add_child(chip)
		chips.append(chip)

	track = Control.new()
	track.custom_minimum_size = Vector2(0, 44)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.draw.connect(_draw_track)
	top.add_child(track)

	# messages on a parchment strip
	msg_panel = PanelContainer.new()
	var pill := _round(Color(0.96, 0.9, 0.74, 0.94), 16, 3, Color("6b4a2c"))
	pill.set_content_margin_all(6)
	pill.content_margin_left = 18
	pill.content_margin_right = 18
	msg_panel.add_theme_stylebox_override("panel", pill)
	msg_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	msg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(msg_panel)
	lbl_msg = _label(22)
	lbl_msg.add_theme_color_override("font_color", Color("2a2118"))
	lbl_msg.add_theme_constant_override("outline_size", 0)
	lbl_msg.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl_msg.custom_minimum_size = Vector2(300, 0)
	msg_panel.add_child(lbl_msg)

	lbl_hint = _label(30)
	lbl_hint.text = "TAP ANYWHERE TO ROLL"
	lbl_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	lbl_hint.offset_left = -260
	lbl_hint.offset_right = 260
	lbl_hint.offset_top = -352
	lbl_hint.offset_bottom = -304
	lbl_hint.add_theme_color_override("font_color", Color("ffe08a"))
	lbl_hint.add_theme_font_size_override("font_size", 34)
	lbl_hint.visible = false
	safe.add_child(lbl_hint)

	lbl_note = _label(22)  # weather and time notices
	lbl_note.add_theme_color_override("font_color", Color("fff3c4"))
	lbl_note.modulate.a = 0.0
	top.add_child(lbl_note)

	lbl_big = _label(64)   # rewards and big events, centre screen
	lbl_big.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	lbl_big.offset_top = 400
	lbl_big.offset_bottom = 500
	lbl_big.pivot_offset = Vector2(get_viewport().get_visible_rect().size.x / 2.0, 50)
	lbl_big.add_theme_constant_override("outline_size", 18)
	lbl_big.modulate.a = 0.0
	layer.add_child(lbl_big)

	for at_top in [true, false]:  # letterbox bars, closed for the opening scene
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if at_top else Control.PRESET_BOTTOM_WIDE)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(bar)
		bars.append(bar)

	flash_rect = ColorRect.new()
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.color = Color(1, 0, 0, 0)
	layer.add_child(flash_rect)

	# landing card: appears after a roll and says what it leads to
	card = PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	card.offset_left = -250
	card.offset_right = 250
	card.offset_top = 300
	card.offset_bottom = 400
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.visible = false
	safe.add_child(card)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 14)
	crow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(crow)
	card_icon = TextureRect.new()
	card_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	card_icon.custom_minimum_size = Vector2(78, 78)
	card_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crow.add_child(card_icon)
	var cwords := VBoxContainer.new()
	cwords.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cwords.alignment = BoxContainer.ALIGNMENT_CENTER
	cwords.add_theme_constant_override("separation", -2)
	cwords.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crow.add_child(cwords)
	card_title = _label(30)
	card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cwords.add_child(card_title)
	card_sub = _label(21)
	card_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	card_sub.add_theme_color_override("font_color", Color("f3e3b8"))
	card_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cwords.add_child(card_sub)

	# reward reveal: spinning sunburst, big icon, caption
	var vw := get_viewport().get_visible_rect().size.x
	reward_root = Control.new()
	reward_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reward_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reward_root.visible = false
	layer.add_child(reward_root)
	reward_rays = Control.new()
	reward_rays.position = Vector2(vw / 2.0, 600)
	reward_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reward_rays.draw.connect(_draw_rays)
	reward_root.add_child(reward_rays)
	reward_icon = TextureRect.new()
	reward_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	reward_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	reward_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	reward_icon.size = Vector2(240, 240)
	reward_icon.pivot_offset = Vector2(120, 120)
	reward_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reward_root.add_child(reward_icon)
	reward_lbl = _label(60)
	reward_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	reward_lbl.offset_top = 750
	reward_lbl.offset_bottom = 840
	reward_lbl.add_theme_constant_override("outline_size", 16)
	reward_root.add_child(reward_lbl)

	turn_bar = make_meter(Color("ffd76a"))
	turn_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	turn_bar.offset_left = -90
	turn_bar.offset_right = 90
	turn_bar.offset_top = -116
	turn_bar.offset_bottom = -70
	turn_bar.visible = false
	safe.add_child(turn_bar)

	# the die is the roll button
	die = Control.new()
	die.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	die.offset_left = -85
	die.offset_right = 85
	die.offset_top = -296
	die.offset_bottom = -126
	die.pivot_offset = Vector2(85, 85)
	die.draw.connect(_draw_die)
	die.gui_input.connect(_die_input)
	safe.add_child(die)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 110
	bottom.offset_right = -110
	bottom.offset_top = -250
	bottom.offset_bottom = -80
	bottom.add_theme_constant_override("separation", 12)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(bottom)
	jump_bar = make_meter(Color("ff7043"))
	jump_bar.modulate.a = 0.0
	bottom.add_child(jump_bar)
	btn_row = HBoxContainer.new()
	btn_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(btn_row)
	me_bar = Control.new()
	me_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	me_bar.offset_left = 14
	me_bar.offset_right = 254
	me_bar.offset_top = -176
	me_bar.offset_bottom = -58
	me_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	me_bar.draw.connect(_draw_me)
	safe.add_child(me_bar)
	pause_btn = Button.new()
	pause_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_btn.offset_left = -84
	pause_btn.offset_right = -14
	pause_btn.offset_top = 168
	pause_btn.offset_bottom = 238
	pause_btn.add_theme_stylebox_override("normal", _round(Color(0.42, 0.29, 0.17, 0.9), 35, 4, Color("ffd76a")))
	pause_btn.add_theme_stylebox_override("hover", _round(Color(0.51, 0.38, 0.24, 0.95), 35, 4, Color("ffd76a")))
	pause_btn.add_theme_stylebox_override("pressed", _round(Color(0.32, 0.22, 0.12, 0.95), 35, 4, Color("c98a1e")))
	pause_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	pause_btn.draw.connect(_draw_pause.bind(pause_btn))
	pause_btn.pressed.connect(toggle_pause)
	safe.add_child(pause_btn)
	hud_nodes = [top, die, bottom, lbl_hint, turn_bar, lbl_big, me_bar, pause_btn]

	lbl_count = _label(300)
	lbl_count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_count.pivot_offset = get_viewport().get_visible_rect().size / 2.0
	lbl_count.add_theme_constant_override("outline_size", 44)
	lbl_count.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	lbl_count.add_theme_constant_override("shadow_offset_y", 14)
	lbl_count.modulate.a = 0.0
	layer.add_child(lbl_count)

	# pause screen: dim the game, tablet with the choices
	pause_panel = Control.new()
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.visible = false
	layer.add_child(pause_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.01, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(dim)
	var pcol := VBoxContainer.new()
	pcol.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pcol.offset_left = 70
	pcol.offset_right = -70
	pcol.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_panel.add_child(pcol)
	var ptab := PanelContainer.new()
	ptab.add_theme_stylebox_override("panel", _tablet())
	pcol.add_child(ptab)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 18)
	ptab.add_child(pv)
	title(pv, "PAUSED", 60, GOLD)
	menu_button(pv, "RESUME", Color("3fae5a"), toggle_pause, true, 42)
	menu_button(pv, "RESTART", Color("ee8a1c"), restart_race, true, 36)
	menu_button(pv, "EXIT TO LOBBY", Color("6b4a2c"), exit_to_lobby, true, 36)

	lobby = Control.new()
	lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lobby.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(lobby)

	results = PanelContainer.new()
	results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results.offset_left = 60
	results.offset_right = -60
	results.offset_top = 300
	results.offset_bottom = -330
	results.add_theme_stylebox_override("panel", _tablet())
	results.visible = false
	safe.add_child(results)


func _die_input(e: InputEvent) -> void:
	var pressed: bool = (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed
	if await_roll and pressed:
		await_roll = false
		rolled.emit()


func _heart(c: Control, at: Vector2, full: bool) -> void:
	var t := ui_tex("heart" if full else "heart_empty")
	if t:
		c.draw_texture_rect(t, Rect2(at - Vector2(2, 3), Vector2(22, 22)), false)
		return
	var col := Color("e2463a") if full else Color("5a4636")
	c.draw_rect(Rect2(at + Vector2(2, 0), Vector2(6, 4)), col)
	c.draw_rect(Rect2(at + Vector2(10, 0), Vector2(6, 4)), col)
	c.draw_rect(Rect2(at + Vector2(0, 4), Vector2(18, 6)), col)
	c.draw_rect(Rect2(at + Vector2(2, 10), Vector2(14, 3)), col)
	c.draw_rect(Rect2(at + Vector2(5, 13), Vector2(8, 3)), col)
	c.draw_rect(Rect2(at + Vector2(7, 16), Vector2(4, 2)), col)


func _frame(id: String, frac: float, tint := Color.WHITE) -> StyleBox:
	# 9-sliced painted frame; margins are a fraction of the texture's width
	var t := ui_tex(id)
	if t == null:
		return null
	var s := StyleBoxTexture.new()
	s.texture = t
	var m := float(t.get_width()) * frac
	s.texture_margin_left = m
	s.texture_margin_right = m
	s.texture_margin_top = m
	s.texture_margin_bottom = m
	s.modulate_color = tint
	return s


func _bar() -> StyleBox:
	# thin dark gold-rimmed strip: stats, race track, timers
	var t := ui_tex("bar_dark")
	if t == null:
		return _round(Color(0.13, 0.09, 0.06, 0.88), 16, 4, Color("ffd76a"))
	var s := StyleBoxTexture.new()
	s.texture = t
	var h := float(t.get_height())
	s.texture_margin_left = h * 0.55
	s.texture_margin_right = h * 0.55
	s.texture_margin_top = h * 0.34
	s.texture_margin_bottom = h * 0.4
	return s


func make_meter(c: Color) -> Control:
	# framed bar that drains; used for the roll timer and the jump window
	var m := Control.new()
	m.custom_minimum_size = Vector2(0, 46)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.set_meta("v", 1.0)
	m.set_meta("c", c)
	m.draw.connect(_draw_meter.bind(m))
	return m


func set_meter(m: Control, v: float) -> void:
	m.set_meta("v", clampf(v, 0.0, 1.0))
	m.queue_redraw()


func _draw_meter(m: Control) -> void:
	m.draw_style_box(_bar(), Rect2(Vector2.ZERO, m.size))
	var v: float = m.get_meta("v")
	var c: Color = m.get_meta("c")
	if v < 0.35:  # turns red as it runs out
		c = c.lerp(Color("ff4a3a"), 1.0 - v / 0.35)
	var inset := Vector2(17, 13)
	var w := (m.size.x - inset.x * 2.0) * v
	if w > 3.0:
		var h := m.size.y - inset.y * 2.0 - 4.0
		m.draw_style_box(_round(c, 5), Rect2(inset, Vector2(w, h)))
		m.draw_rect(Rect2(inset + Vector2(3, 2), Vector2(w - 6, 4)), c.lightened(0.45))


func _icon(c: Control, id: String, at: Vector2, size: float, fallback: Color) -> void:
	var t := ui_tex(id)
	if t:
		c.draw_texture_rect(t, Rect2(at, Vector2(size, size)), false)
	else:
		c.draw_rect(Rect2(at + Vector2(2, 2), Vector2(size - 4, size - 4)), fallback)


func _face(c: Control, at: Vector2, s: float, col: Color, rim: Color) -> void:
	# little hat-wearing explorer face in the player's colour
	var f := s / 46.0
	c.draw_rect(Rect2(at - Vector2(3, 3), Vector2(s + 6, s + 6)), rim)
	c.draw_rect(Rect2(at, Vector2(s, s)), col)
	c.draw_rect(Rect2(at + Vector2(9, 17) * f, Vector2(28, 25) * f), Color("c68e5f"))
	c.draw_rect(Rect2(at + Vector2(3, 11) * f, Vector2(40, 8) * f), Color("b08d57"))
	c.draw_rect(Rect2(at + Vector2(11, 3) * f, Vector2(24, 10) * f), Color("9a7a48"))
	c.draw_rect(Rect2(at + Vector2(14, 26) * f, Vector2(5, 6) * f), Color("2a2118"))
	c.draw_rect(Rect2(at + Vector2(27, 26) * f, Vector2(5, 6) * f), Color("2a2118"))


func standings() -> Dictionary:
	# live ranking: finishers in order, then runners by how far along, then those knocked out
	var order: Array[Dictionary] = []
	order.append_array(finished)
	var rest: Array[Dictionary] = []
	for p in players:
		if not p.done:
			rest.append(p)
	rest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (not a.out and b.out) or (a.out == b.out and a.pos > b.pos))
	order.append_array(rest)
	var out := {}
	for k in order.size():
		out[order[k].name] = k + 1
	return out


func _medal(c: Control, at: Vector2, rank: int, size: float) -> void:
	# round rank medal: gold, silver, bronze, then plain
	var col: Color = [GOLD, Color("d9dde2"), Color("d08a4a")][rank - 1] if rank <= 3 else Color("7a6a55")
	var r := size / 2.0
	c.draw_circle(at + Vector2(r, r), r + 2.0, Color("2a2118"))
	c.draw_circle(at + Vector2(r, r), r, col)
	c.draw_circle(at + Vector2(r, r) - Vector2(r, r) * 0.3, r * 0.3, col.lightened(0.45))
	c.draw_string(ui_font, at + Vector2(0, size * 0.74), str(rank), HORIZONTAL_ALIGNMENT_CENTER, size, int(size * 0.72), Color("2a2118"))


func _draw_chip(k: int) -> void:
	# Player plaque on the live leaderboard. Wide (up to 4 players): face and
	# rank medal on the left; name, slab, lives and respawns filling the rest.
	# Narrow (5-6 players): stacked.
	if k >= players.size():
		return
	var c := chips[k]
	var p := players[k]
	var on: bool = not hud_current.is_empty() and hud_current.name == p.name
	var col: Color = p.color
	var w := c.size.x
	var oy := 0.0 if on else 6.0   # whoever's turn it is lifts up
	var dark := Color("2a2118")
	var plate := _frame("token", 0.2, Color(1.35, 1.25, 0.95) if on else Color(0.82, 0.82, 0.82))
	if plate == null:
		plate = _round(col.darkened(0.45) if on else Color("2e2118"), 14, 5, Color("ffd76a") if on else Color("8a6a3a"))
	c.draw_style_box(plate, Rect2(0, oy, w, c.size.y - 8))
	var rim := Color("5fe0ff") if p.shield else (Color("fff8e1") if k == 0 else dark)
	var rank: int = standings().get(p.name, k + 1)
	var state := "%d" % p.pos
	if p.out:
		state = "OUT"
	elif p.done:
		state = "DONE"
	var n := maxi(3, p.hearts)
	if w >= 140.0:
		c.draw_rect(Rect2(14, oy + 14, w - 28, c.size.y - 36), Color(col.r, col.g, col.b, 0.28 if on else 0.14))  # colour wash
		_face(c, Vector2(18, oy + 22), 46, col, rim)
		_medal(c, Vector2(48, oy + 52), rank, 24)
		var rx := 80.0
		c.draw_string_outline(ui_font, Vector2(rx, oy + 36), p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, 5, dark)
		c.draw_string(ui_font, Vector2(rx, oy + 36), p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("fff8e1") if on else Color("d8c9a0"))
		c.draw_string_outline(ui_font, Vector2(w - 70, oy + 40), state, HORIZONTAL_ALIGNMENT_RIGHT, 54, 26, 6, dark)
		c.draw_string(ui_font, Vector2(w - 70, oy + 40), state, HORIZONTAL_ALIGNMENT_RIGHT, 54, 26, GOLD)
		for h in n:
			_icon(c, "heart" if h < p.hearts else "heart_empty", Vector2(rx + h * 18.0, oy + 46), 19, Color("e2463a") if h < p.hearts else Color("5a4636"))
		for r in p.revives:
			_icon(c, "ankh", Vector2(w - 38 - r * 19.0, oy + 46), 20, Color("5fe0ff"))
		if p.banana > 0:
			_icon(c, "banana", Vector2(rx + n * 18.0 + 4, oy + 45), 21, Color("ffe066"))
	else:
		var s := 34.0
		var at := Vector2((w - s) / 2.0, oy + 10.0)
		_face(c, at, s, col, rim)
		_medal(c, Vector2(7, oy + 8), rank, 20)
		c.draw_string_outline(ui_font, Vector2(0, at.y + s + 20), state, HORIZONTAL_ALIGNMENT_CENTER, w, 20, 6, dark)
		c.draw_string(ui_font, Vector2(0, at.y + s + 20), state, HORIZONTAL_ALIGNMENT_CENTER, w, 20, GOLD)
		var x0 := (w - n * 13.0) / 2.0
		for h in n:
			_icon(c, "heart" if h < p.hearts else "heart_empty", Vector2(x0 + h * 13.0, at.y + s + 22), 14, Color("e2463a") if h < p.hearts else Color("5a4636"))
		for r in p.revives:  # respawns as small ankhs down the right edge
			_icon(c, "ankh", Vector2(w - 26, oy + 12 + r * 15.0), 15, Color("5fe0ff"))
		if p.banana > 0:
			_icon(c, "banana", Vector2(6, oy + c.size.y - 36), 22, Color("ffe066"))
	if p.skip > 0:
		c.draw_string(ui_font, Vector2(w - 30, oy + 24), "zz", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("9fb4ff"))
	if p.wounded > 0:  # healing: red cross badge with own turns left
		var bx := w - 34.0
		var by := oy + c.size.y - 40.0
		c.draw_rect(Rect2(bx - 2, by - 2, 26, 26), dark)
		c.draw_rect(Rect2(bx, by, 22, 22), Color("f6f1e4"))
		c.draw_rect(Rect2(bx + 8, by + 3, 6, 16), Color("d6402e"))
		c.draw_rect(Rect2(bx + 3, by + 8, 16, 6), Color("d6402e"))
		c.draw_string(ui_font, Vector2(bx - 16, by + 19), str(p.wounded), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("ff8a7a"))
	if p.out:
		c.draw_rect(Rect2(0, oy, w, c.size.y - 8), Color(0.1, 0.1, 0.1, 0.6))


func _draw_me() -> void:
	# your own kit in the bottom-left corner, large: lives on top, coins and respawns below
	if players.is_empty():
		return
	var p := players[0]
	var c := me_bar
	c.draw_style_box(_round(Color(0.1, 0.07, 0.05, 0.9), 16, 5, Color("ffd76a")), Rect2(Vector2.ZERO, c.size))
	for h in maxi(3, p.hearts):
		_icon(c, "heart" if h < p.hearts else "heart_empty", Vector2(14 + h * 40.0, 12), 40, Color("e2463a") if h < p.hearts else Color("5a4636"))
	_icon(c, "coin", Vector2(14, 62), 38, GOLD)
	c.draw_string_outline(ui_font, Vector2(58, 94), str(p.coins), HORIZONTAL_ALIGNMENT_LEFT, -1, 32, 6, Color("2a2118"))
	c.draw_string(ui_font, Vector2(58, 94), str(p.coins), HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color("fff8e1"))
	for r in p.revives:
		_icon(c, "ankh", Vector2(124 + r * 36.0, 62), 40, Color("5fe0ff"))
	if p.shield:
		_icon(c, "shield", Vector2(c.size.x - 52, 62), 40, Color("3f7fe0"))
	if p.banana > 0:
		_icon(c, "banana", Vector2(c.size.x - 52, 12), 40, Color("ffe066"))
	if p.wounded > 0:
		c.draw_string_outline(ui_font, Vector2(0, -8), "HEALING: %d" % p.wounded, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 22, 6, Color("2a2118"))
		c.draw_string(ui_font, Vector2(0, -8), "HEALING: %d" % p.wounded, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 22, Color("ff8a7a"))
	if active(p) and round_no >= 4 and p.pos - bo <= 6:  # the boulder is close behind you
		var by := -34.0 if p.wounded > 0 else -8.0
		var warn := "BOULDER %d BEHIND" % maxi(0, p.pos - bo)
		c.draw_string_outline(ui_font, Vector2(0, by), warn, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 22, 6, Color("2a2118"))
		c.draw_string(ui_font, Vector2(0, by), warn, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 22, Color("ffb347") if p.pos - bo > 3 else Color("ff5a4a"))


func _draw_rays() -> void:
	# sunburst behind a reward
	for k in 12:
		var a0 := k * TAU / 12.0
		var a1 := a0 + TAU / 24.0
		reward_rays.draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(cos(a0), sin(a0)) * 330.0, Vector2(cos(a1), sin(a1)) * 330.0]), Color(1.0, 0.86, 0.35, 0.5))
	reward_rays.draw_circle(Vector2.ZERO, 150, Color(1.0, 0.93, 0.6, 0.35))


func reward(p: Dictionary, icon_id: String, text: String, c: Color) -> void:
	# A prize is revealed big in the middle of the screen, then flies into the
	# winner's token in the HUD, which bounces as it lands.
	var k := players.find(p)
	var vw := get_viewport().get_visible_rect().size.x
	reward_icon.texture = ui_tex(icon_id) if icon_id != "" else null
	reward_icon.position = Vector2(vw / 2.0 - 120, 480)
	reward_icon.scale = Vector2(0.2, 0.2)
	reward_icon.modulate.a = 1.0
	reward_rays.modulate.a = 1.0
	reward_rays.scale = Vector2(0.3, 0.3)
	reward_lbl.text = text
	reward_lbl.add_theme_color_override("font_color", c)
	reward_lbl.modulate.a = 1.0
	reward_root.visible = true
	sfx.play("good")
	sfx.play("coin", -3.0)
	burst(p.a.position + Vector3(0, 1.5, 0), GOLD, 26, 6.0)
	var tw := reward_root.create_tween().set_parallel()
	tw.tween_property(reward_icon, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(reward_rays, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await wait(1.15)
	var chip := chips[k]
	var target := chip.global_position + chip.size / 2.0 - Vector2(120, 120)
	var fly := reward_root.create_tween().set_parallel()
	fly.tween_property(reward_icon, "position", target, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	fly.tween_property(reward_icon, "scale", Vector2(0.16, 0.16), 0.42)
	fly.tween_property(reward_rays, "modulate:a", 0.0, 0.25)
	fly.tween_property(reward_lbl, "modulate:a", 0.0, 0.3)
	await fly.finished
	reward_root.visible = false
	sfx.play("coin")
	chip.pivot_offset = chip.size / 2.0
	chip.scale = Vector2(1.3, 1.3)
	chip.create_tween().tween_property(chip, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	refresh_ui()


func _draw_track() -> void:
	# Race bar. A framed strip from start to gate with a gold fill up to the
	# leader and a tick every 20 slabs. Each runner is a round pin in their
	# colour that glides along as they move; the boulder is a grey rock; the
	# pin of whoever's turn it is stands larger and bobs.
	var y := track.size.y / 2.0 + 6.0
	var x0 := 16.0
	var w := track.size.x - 62.0
	var dark := Color("2a2118")
	track.draw_style_box(_round(Color(0.1, 0.07, 0.05, 0.88), 9, 3, Color("c98a1e")), Rect2(0, y - 9, track.size.x - 26, 18))
	var lead := 0.0
	for p in players:
		if not p.out:
			lead = maxf(lead, float(pin_at.get(p.name, 0.0)))
	if lead > 0.2:
		track.draw_style_box(_round(Color(1.0, 0.82, 0.3, 0.55), 5), Rect2(x0 - 8, y - 4, lead / END * w + 8, 8))
	for t in [20, 40, 60]:
		track.draw_rect(Rect2(x0 + float(t) / END * w - 1, y - 6, 2, 12), Color(1, 0.95, 0.75, 0.4))
	_icon(track, "trophy", Vector2(track.size.x - 40, y - 22), 40, GOLD)
	var bx := clampf(pin_bo / END, 0.0, 1.0) * w + x0
	track.draw_circle(Vector2(bx, y), 12, dark)
	track.draw_circle(Vector2(bx, y), 9, Color("8a8478"))
	track.draw_circle(Vector2(bx - 3, y - 3), 3.5, Color("b3ada1"))
	# whoever's turn it is is drawn last, on top
	var order: Array[Dictionary] = []
	for p in players:
		if not p.out and (hud_current.is_empty() or p.name != hud_current.name):
			order.append(p)
	for p in players:
		if not p.out and not hud_current.is_empty() and p.name == hud_current.name:
			order.append(p)
	for p in order:
		var on: bool = not hud_current.is_empty() and p.name == hud_current.name
		var x: float = float(pin_at.get(p.name, 0.0)) / END * w + x0
		var col: Color = p.color
		var r := 12.0 if on else 9.0
		var py := y - 15.0 - (absf(sin(clock * 5.0)) * 4.0 if on else 0.0)
		track.draw_colored_polygon(PackedVector2Array([Vector2(x - r * 0.7, py + r * 0.5), Vector2(x + r * 0.7, py + r * 0.5), Vector2(x, y + 1)]), dark)  # pointer down to the bar
		track.draw_circle(Vector2(x, py), r + 3.0, Color("fff8e1") if not p.bot else dark)
		track.draw_circle(Vector2(x, py), r, col)
		track.draw_circle(Vector2(x - r * 0.3, py - r * 0.3), r * 0.3, col.lightened(0.5))


func _draw_die() -> void:
	if die_val == 0:
		return
	var r := Rect2(Vector2.ZERO, die.size)
	var face := ui_tex("die")
	if face:
		die.draw_texture_rect(face, Rect2(Vector2(0, r.size.y * 0.05), r.size), false, Color(0, 0, 0, 0.45))  # drop shadow
		die.draw_texture_rect(face, r, false)
	else:
		die.draw_style_box(_round(Color("2a2118"), 32), Rect2(Vector2(0, 12), r.size))
		die.draw_style_box(_round(Color("fbf6e6"), 32, 6), r)
	var pips := {1: [4], 2: [0, 8], 3: [0, 4, 8], 4: [0, 2, 6, 8], 5: [0, 2, 4, 6, 8], 6: [0, 2, 3, 5, 6, 8]}
	for k in pips[die_val]:
		var cell := Vector2(k % 3, k / 3)
		var at := r.size * (Vector2(0.27, 0.27) + cell * 0.23)
		var u := r.size.x / 210.0
		die.draw_circle(at, 17 * u, Color("2a2118"))
		die.draw_circle(at, 13 * u, die_color.darkened(0.15))
		die.draw_circle(at + Vector2(-4, -4) * u, 4 * u, die_color.lightened(0.5))


func set_die(v: int, pop := false) -> void:
	die_val = v
	die.rotation = 0.0 if pop or v == 0 else rng.randf_range(-0.25, 0.25)
	if pop:
		die.scale = Vector2(1.45, 1.45)
		create_tween().tween_property(die, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	die.queue_redraw()


func clear_buttons() -> void:
	for c in btn_row.get_children():
		c.queue_free()


func add_button(text: String, c: Color, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_theme_font_override("font", ui_font)
	b.add_theme_font_size_override("font_size", 46)
	b.add_theme_constant_override("outline_size", 12)
	b.add_theme_color_override("font_outline_color", Color("2a2118"))
	for n in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(n, Color("fff8e1"))
	b.add_theme_stylebox_override("normal", _btn_style(c, false))
	b.add_theme_stylebox_override("hover", _btn_style(c.lightened(0.08), false))
	b.add_theme_stylebox_override("pressed", _btn_style(c.darkened(0.12), true))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func() -> void: sfx.play("step"))
	b.pressed.connect(cb)
	btn_row.add_child(b)


func refresh_ui(current: Dictionary = {}) -> void:
	if not current.is_empty():
		hud_current = current
	for c in chips:
		c.queue_redraw()
	me_bar.queue_redraw()
	track.queue_redraw()


func say(text: String) -> void:
	# short message pill; fades by itself so it never sits over the view
	lbl_msg.text = text
	msg_panel.visible = text != ""
	msg_panel.modulate.a = 1.0
	if msg_tw:
		msg_tw.kill()
	msg_tw = msg_panel.create_tween()
	msg_tw.tween_interval(2.8)
	msg_tw.tween_property(msg_panel, "modulate:a", 0.0, 0.6)


func place_die(big: bool) -> void:
	# centre-stage on your own turn; tucked in the corner while a bot rolls
	var vw := get_viewport().get_visible_rect().size.x
	if big:
		die.offset_left = -85
		die.offset_right = 85
		die.offset_top = -296
		die.offset_bottom = -126
	else:
		die.offset_left = vw / 2.0 - 132
		die.offset_right = vw / 2.0 - 22
		die.offset_top = -168
		die.offset_bottom = -58
	die.pivot_offset = (Vector2(die.offset_right - die.offset_left, die.offset_bottom - die.offset_top)) / 2.0


# ---------------------------------------------------------------- game flow

func prepare_world() -> void:
	bo = -6
	round_no = 0
	style = STYLES[rng.randi_range(0, STYLES.size() - 1)]
	tod = [0.03, 0.2, 0.4, 0.66][rng.randi_range(0, 3)]  # start at dawn, noon, late day or dusk
	rain = rng.randf() < 0.3
	rain_k = 1.0 if rain else 0.0
	weather_in = rng.randf_range(30, 60)
	was_night = false
	if OS.has_environment("VAULT_TOD"):  # dev: force time of day and weather for screenshots
		tod = float(OS.get_environment("VAULT_TOD"))
		rain = OS.get_environment("VAULT_RAIN") != ""
		rain_k = 1.0 if rain else 0.0
		weather_in = 9999.0
	hud_current = {}
	gen_path()
	gen_board()
	build_world()
	clear_buttons()
	set_die(0)
	say("%s. First to the treasure wins!" % style.name)
	for k in chips.size():
		chips[k].visible = k < players.size()
	refresh_ui()


func start_run() -> void:
	prepare_world()
	await intro()
	play()


func play() -> void:
	var me := players[0]
	while true:
		for p in players:
			if not active(p):
				continue
			await take_turn(p)
			if not active(me):
				game_over(me)
				return
		round_no += 1
		await boulder_turn()
		if not active(me):
			game_over(me)
			return


func take_turn(p: Dictionary) -> void:
	focus_p = p
	if p.wounded > 0:  # one own turn closer to healed
		p.wounded -= 1
		if p.wounded == 0:
			p.a.wounded = false
			popup(p.a.position, "HEALED", Color("7dff9b"))
			burst(p.a.position + Vector3(0, 1.2, 0), Color("7dff9b"), 10, 3.0)
			sfx.play("good", -8.0)
		refresh_ui(p)
	if p.skip > 0:
		p.skip -= 1
		say("%s missed this turn, recovering" % subj(p))
		refresh_ui(p)
		await wait(0.9)
		return
	var again := true
	while again and active(p):
		again = false
		refresh_ui(p)
		var n: int = await roll(p)
		if n == 0:
			break
		var steps := n
		var lead := 0
		for q in players:
			if active(q) or q.done:
				lead = maxi(lead, q.pos)
		var gap: int = lead - p.pos
		var boost := 3 if gap >= 26 else (2 if gap >= 14 else 0)
		if boost > 0:  # runners far behind get a tailwind, so the race stays a race
			steps += boost
			popup(p.a.position, "TAILWIND +%d" % boost, Color("5fe0ff"))
			burst(p.a.position + Vector3(0, 1, 0), Color("5fe0ff"), 12, 4.0)
			sfx.play("good", -8.0, 1.3)
		var trail := show_trail(p, steps)
		await wait(preview(p, steps))
		p.a.express("")
		await move(p, steps)
		if is_instance_valid(trail):
			trail.queue_free()
		if active(p):
			p.a.rotation.y = yaws[mini(p.pos, END)]
		refresh_ui(p)
		if n == 6 and active(p) and p.skip == 0:
			again = true
			say("%s rolled a six. Roll again!" % subj(p))
			await wait(0.5)
	set_die(0)
	spot_off()
	await wait(1.0)  # hold on this runner so the result can sink in before the camera moves on


func show_card(icon_id: String, title_text: String, sub: String, c: Color, secs: float) -> void:
	card_icon.texture = ui_tex(icon_id) if icon_id != "" else null
	card_icon.visible = card_icon.texture != null
	card_title.text = title_text
	card_title.add_theme_color_override("font_color", c)
	card_sub.text = sub
	card.add_theme_stylebox_override("panel", _round(Color(0.1, 0.07, 0.05, 0.93), 18, 5, c))
	card.visible = true
	card.modulate.a = 1.0
	card.pivot_offset = card.size / 2.0
	card.scale = Vector2(0.6, 0.6)
	if card_tw:
		card_tw.kill()
	card_tw = card.create_tween()
	card_tw.tween_property(card, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	card_tw.tween_interval(secs)
	card_tw.tween_property(card, "modulate:a", 0.0, 0.3)
	card_tw.tween_callback(func() -> void: card.visible = false)


func preview(p: Dictionary, n: int) -> float:
	# Before anyone moves, say plainly what this roll leads to: a card with the
	# slab's picture and effect, and the runner's face reacting. Returns how
	# long to hold before moving.
	var dest := mini(p.pos + n, END)
	var kind: String = kinds[dest]
	var spikes := false
	for i in range(p.pos + 1, dest):
		if kinds[i] == "spike" and not p.hit.has(i):
			spikes = true
	var who: String = "YOU" if not p.bot else p.name
	var red := Color("ff5a4a")
	if dest >= END:
		show_card("trophy", "%s: THE TREASURE!" % who, "This roll reaches the gate", GOLD, 1.3)
		p.a.express("happy")
	elif kind in HARMFUL and p.hit.has(dest):
		show_card("", "%s: A KNOWN TRAP" % who, "Caught once already: dodged this time", Color("7dff9b"), 1.2)
	elif kind == "rope":
		show_card("s_rope", "%s: ROPE!" % who, "Swing ahead %d slabs" % (rope_to[dest] - dest), Color("3fe07a"), 1.3)
		p.a.express("happy")
	elif kind == "snake":
		show_card("s_snake", "%s: COBRA!" % who, "Thrown back %d slabs" % (dest - snake_to[dest]), red, 1.4)
		p.a.express("scared")
	elif kind == "tiger":
		show_card("s_tiger", "%s: TIGER!" % who, "Lose a life and flee back", red, 1.4)
		p.a.express("scared")
	elif kind == "crumble":
		show_card("s_crumble", "%s: CRACKED SLAB!" % who, "It gives way: lose a life", Color("ff9a2e"), 1.4)
		p.a.express("scared")
	elif kind == "spike":
		show_card("s_spike", "%s: SPIKES!" % who, "Tap in time to jump them", red, 1.3)
		p.a.express("scared")
	elif kind == "mystery":
		show_card("s_mystery", "%s: MYSTERY" % who, "An animal or a treasure chest", Color("b06aff"), 1.2)
		p.a.express("wow")
	elif spikes:
		show_card("s_spike", "%s: SPIKES ON THE WAY" % who, "Tap in time to jump them", red, 1.2)
		p.a.express("scared")
	else:
		return 0.4
	sfx.play("step", -2.0, 0.8)
	return 1.25


func show_trail(p: Dictionary, n: int) -> Node3D:
	# After a roll: glowing dots on each slab to be crossed and a bright frame on
	# the landing slab, in the roller's colour, so you see where the move ends.
	var t := Node3D.new()
	world.add_child(t)
	var col: Color = p.color
	var last := mini(p.pos + n, END)
	for i in range(p.pos + 1, last + 1):
		var cell := Node3D.new()
		cell.position = path[i]
		cell.rotation.y = yaws[i]
		t.add_child(cell)
		if i < last:
			box(cell, Vector3(0.4, 0.08, 0.4), Vector3(0, 0.07, 0), col).material_override = mat(col, true)
		else:
			var lit := col.lightened(0.5)
			if kinds[i] in HARMFUL and not p.hit.has(i):
				lit = Color("ff5a4a")  # danger
			elif kinds[i] == "rope" or i >= END:
				lit = Color("5fff8a")  # good news
			for e in [-1.0, 1.0]:
				box(cell, Vector3(2.3, 0.14, 0.2), Vector3(0, 0.12, e * 1.08), lit).material_override = mat(lit, true)
				box(cell, Vector3(0.2, 0.14, 2.3), Vector3(e * 1.08, 0.12, 0), lit).material_override = mat(lit, true)
			for k in 3:  # arrow hovering over the landing slab
				box(cell, Vector3(0.6 - k * 0.2, 0.16, 0.18), Vector3(0, 1.9 - k * 0.16, 0), lit).material_override = mat(lit, true)
	return t


func roll(p: Dictionary) -> int:
	# returns 1-6, or 0 when the player let the timer run out
	die_color = p.color
	place_die(not is_bot(p))
	if is_bot(p):
		say("%s rolls" % p.name)
		await wait(0.2)
	else:
		say("Your turn. Roll before the bar runs out")
		set_die(5)
		lbl_hint.visible = true
		turn_bar.visible = true
		var pulse := die.create_tween().set_loops()
		pulse.tween_property(die, "scale", Vector2(1.1, 1.1), 0.35)
		pulse.tween_property(die, "scale", Vector2.ONE, 0.35)
		await_roll = true
		var left := ROLL_TIME
		while await_roll and left > 0.0:
			await frame()
			left -= get_process_delta_time()
			set_meter(turn_bar, left / ROLL_TIME)
		pulse.kill()
		die.scale = Vector2.ONE
		lbl_hint.visible = false
		turn_bar.visible = false
		if await_roll:
			await_roll = false
			set_die(0)
			sfx.play("bad")
			say("You ran out of time. Turn lost")
			announce("TIME UP", Color("ff6b5e"))
			await wait(1.0)
			return 0
	sfx.play("dice")
	for k in 6:
		set_die(rng.randi_range(1, 6))
		await wait(0.04)
	var n := rng.randi_range(1, 6)
	set_die(n, true)
	await wait(0.25)
	return n


func move(p: Dictionary, n: int) -> void:
	var root: Node3D = p.a
	p.a.run = true
	for s in n:
		if p.pos >= END:
			break
		var nxt: int = p.pos + 1
		root.turn_to(yaws[p.pos])  # corners are turned smoothly, not snapped
		if kinds[nxt] == "spike":
			if await jump_phase(p, nxt):
				p.pos = nxt
			else:
				break
		else:
			await stride(p, nxt)
			sfx.play("step", -7.0)
			burst(root.position, STONE.lightened(0.2), 4, 1.8)
			p.pos = nxt
			if nxt % 5 == 0:  # torches flare as a runner passes
				sfx.play("fire", -8.0)
				for side in [-1.08, 1.08]:
					burst(path[nxt] + Vector3(side, 1.5, 0).rotated(Vector3.UP, yaws[nxt]), Color("ff9a2e"), 9, 4.5)
		collect(p)
		refresh_ui(p)
	p.a.run = false
	if p.pos >= END:
		p.done = true
		finished.append(p)
		for k in 3:
			burst(root.position + Vector3(0, 1.5, 0), [GOLD, Color("fff8e1"), p.color][k], 26, 8.0)
		popup(root.position, "#%d" % finished.size(), GOLD)
		sfx.play("win")
		root.pose = "cheer"
		fireworks(root.position)
		shake(0.3)
		if finished.size() == 1:
			announce("YOU WIN!" if not p.bot else "%s WINS!" % p.name, GOLD)
		say("%s reached the treasure!" % subj(p))
		await wait(1.7)
		return
	await settle(p)
	await bump(p)


func stride(p: Dictionary, nxt: int) -> void:
	# One step to the next slab. Hurdles are cleared with a parkour move, and
	# now and then a runner throws in a flourish just for style.
	var root: Node3D = p.a
	var style := ""
	if hurdles.has(nxt):
		style = "slide" if hurdles[nxt] == "beam" else ["vault", "flip"][rng.randi_range(0, 1)]
	elif rng.randf() < 0.12:
		style = ["roll", "spin", "long"][rng.randi_range(0, 2)]
	var dy: float = spot(p, nxt).y - root.position.y
	if dy > 0.9:  # a ledge: spring up, hands on top, swing the legs over
		root.pose = "vault"
		sfx.play("jump", -8.0)
		popup(root.position, "CLIMB!", Color("ffe066"))
		await hop(root, spot(p, nxt), 0.55 + dy * 0.25, 0.5)
		root.pose = ""
		squash(root)
		sfx.play("land", -6.0)
		burst(root.position, STONE.lightened(0.25), 6, 2.0)
		return
	if dy < -0.9:  # a drop: leap off and land heavily
		root.air = true
		sfx.play("jump", -9.0)
		await hop(root, spot(p, nxt), 0.55, 0.45)
		root.air = false
		squash(root)
		shake(0.2)
		sfx.play("land", -2.0, 0.8)
		burst(root.position, STONE.lightened(0.25), 12, 3.0)
		return
	if style == "":
		# a running stride: fast and low, just clearing the gap between slabs;
		# it lifts more when the next slab is a step up
		await hop(root, spot(p, nxt), 0.12 + maxf(0.0, dy) * 0.55 + (0.1 if dy < -0.2 else 0.0), 0.3 + absf(dy) * 0.08)
		return
	root.yaw_goal = NAN
	var yaw: float = yaws[p.pos]
	var dur: float = {"vault": 0.34, "flip": 0.44, "slide": 0.36, "roll": 0.38, "spin": 0.42, "long": 0.42}[style]
	root.pose = {"vault": "vault", "flip": "tuck", "slide": "slide", "roll": "tuck", "spin": "cheer", "long": ""}[style]
	root.air = style == "long"
	if style != "slide" and style != "roll":
		sfx.play("jump", -9.0)
	spotlight(p, 0.42)
	popup(root.position, {"vault": "VAULT!", "flip": "FRONT FLIP!", "slide": "SLIDE!", "roll": "ROLL!", "spin": "SPIN!", "long": "LONG JUMP!"}[style], Color("ffe066"))
	var tw := create_tween()
	tw.tween_method(_parkour.bind(root, root.position, spot(p, nxt), style, yaw), 0.0, 1.0, dur)
	await tw.finished
	root.pose = ""
	root.air = false
	root.rotation = Vector3(0, yaw, 0)
	root.position = spot(p, nxt)
	if style == "slide" or style == "roll":
		burst(root.position, STONE.lightened(0.25), 8, 2.5)
	else:
		sfx.play("land", -6.0)
		squash(root)
	if hurdles.has(nxt) and rng.randf() < 0.6:
		await celebrate(p)
	spot_off()


func celebrate(p: Dictionary) -> void:
	# a quick show-off after clearing a hurdle: fist-pump hop, spin, or flex
	var root: Node3D = p.a
	var kind := rng.randi_range(0, 2)
	burst(root.position + Vector3(0, 1.3, 0), [Color("ffe066"), Color("7dff9b"), Color("5fe0ff")][kind], 9, 3.5)
	sfx.play("good", -11.0, 1.35)
	popup(root.position, ["WHOO!", "SMOOTH!", "EASY!"][kind], Color("ffe066"))
	match kind:
		0:
			root.pose = "cheer"
			await hop(root, root.position, 0.5, 0.26)
		1:
			var tw := root.create_tween()
			tw.tween_property(root, "rotation:y", root.rotation.y + TAU, 0.26)
			await tw.finished
		2:
			root.pose = "guard"
			await wait(0.24)
	root.pose = ""


func fireworks(at: Vector3) -> void:
	# a volley of coloured bursts with pops, and a fountain of coins
	burst(at + Vector3(0, 0.5, 0), GOLD, 46, 9.0)
	var cols := [Color("ff5a5a"), Color("ffe066"), Color("5fe0ff"), Color("7dff9b"), Color("e667b5"), Color("ffffff")]
	for k in 9:
		if not is_instance_valid(world):
			return
		var spot_at := at + Vector3(rng.randf_range(-4, 4), rng.randf_range(3.5, 8), rng.randf_range(-4, 4))
		burst(spot_at, cols[k % cols.size()], 30, 7.0)
		sfx.play("bump", -7.0, rng.randf_range(1.5, 2.2))
		if k % 3 == 0:
			sfx.play("coin", -6.0)
		await wait(0.17)


func _parkour(t: float, root: Node3D, from: Vector3, to: Vector3, style: String, yaw: float) -> void:
	var arc: float = {"vault": 0.75, "flip": 1.4, "slide": 0.0, "roll": 0.25, "spin": 1.0, "long": 1.5, "somersault": 2.3}[style]
	var at := from.lerp(to, t) + Vector3(0, sin(t * PI) * arc, 0)
	match style:
		"flip", "roll", "somersault":
			root.rotation = Vector3(-TAU * t, yaw, 0)
			# turn about the body's middle, not the feet
			at += Vector3(0, 0.9, 0) - root.basis * Vector3(0, 0.9, 0)
		"vault":
			root.rotation = Vector3(-sin(t * PI) * 0.85, yaw, 0)
		"slide":
			root.rotation = Vector3(sin(t * PI) * 1.05, yaw, 0)
		"spin":
			root.rotation = Vector3(0, yaw + TAU * t, 0)
	root.position = at


func jump_phase(p: Dictionary, nxt: int) -> bool:
	var root: Node3D = p.a
	var hit := false
	if p.hit.has(nxt):
		hit = true
	elif is_bot(p):
		await wait(0.3)
		hit = rng.randf() < 0.7
	else:
		jump_hit = false
		jump_open = true
		die.visible = false
		say("SPIKES! TAP TO JUMP")
		add_button("JUMP!", Color("ff5a36"), func() -> void: jump_hit = true)
		jump_bar.modulate.a = 1.0
		var t := 0.0
		while t < JUMP_WINDOW and not jump_hit:
			await frame()
			t += get_process_delta_time()
			set_meter(jump_bar, 1.0 - t / JUMP_WINDOW)
		jump_open = false
		die.visible = true
		jump_bar.modulate.a = 0.0
		clear_buttons()
		hit = jump_hit
	if hit:
		spotlight(p, 0.5)
		say("%s cleared the spikes" % subj(p))
		var sp: Node3D = spikes[nxt]
		var tw := create_tween()
		tw.tween_property(sp, "position:y", -0.9, 0.25)
		tw.tween_interval(1.0)
		tw.tween_property(sp, "position:y", 0.0, 0.25)
		await hop(root, spot(p, nxt), 1.5, 0.42)
		squash(root)
		burst(root.position, Color("fff8e1"), 10, 3.0)
		popup(root.position, "NICE!", Color("ffe066"))
		sfx.play("good", -4.0)
		earn(p, 2)
		spot_off()
		return true
	say("%s hit the spikes!" % subj(p))
	await hop(root, spot(p, nxt), 0.4, 0.2)
	p.pos = nxt
	p.hit[nxt] = true
	shake(0.3)
	await hitstop()
	burst(root.position, Color("e2463a"), 18, 5.0)
	await hurt(p)
	return false


func settle(p: Dictionary, forced := false) -> void:
	# Whatever slab a player ends on triggers, and so does the slab that sends
	# them to. But a runner who was thrown, dragged or knocked there is safe
	# from traps on arrival (only the first landing of a move can hurt), and a
	# trap that has already caught this runner does not catch them twice.
	var seen := {}
	var safe := forced
	while active(p) and not seen.has(p.pos):
		seen[p.pos] = true
		var before: int = p.pos
		collect(p)
		await land(p, safe)
		safe = true
		if p.pos == before:
			break
	p.a.rotation = Vector3(0, yaws[mini(p.pos, END)], 0)


func safe_back(p: Dictionary, d: int) -> int:
	# where a setback really puts a runner: never behind the boulder or right in front of it
	return clampi(maxi(d, bo + 3), 0, p.pos)


func land(p: Dictionary, safe := false) -> void:
	var kind: String = kinds[p.pos]
	if kind in HARMFUL:
		if safe:
			return
		if p.hit.has(p.pos):  # fooled once already: they know this one
			popup(p.a.position, "DODGED!", Color("7dff9b"))
			sfx.play("good", -8.0)
			p.a.express("happy", 0.8)
			await wait(0.5)
			return
		p.hit[p.pos] = true
	match kind:
		"rope":
			await rope_cross(p)
		"snake":
			await snake_strike(p)
		"crumble":
			await crumble(p)
		"mystery":
			await mystery(p)
		"tiger":
			await tiger_attack(p)


# ---- lives and coins

func earn(p: Dictionary, n: int) -> void:
	p.coins += n
	sfx.play("coin")
	popup(p.a.position, "+%d" % n, GOLD)
	burst(p.a.position + Vector3(0, 1.2, 0), GOLD, 6, 3.0)
	if p.coins >= 10 and p.hearts < 5:  # ten coins buy a life
		p.coins -= 10
		p.hearts += 1
		announce("+1 LIFE", Color("7dff9b"))
		sfx.play("good", -4.0)
	refresh_ui()


func collect(p: Dictionary) -> void:
	if pickups.has(p.pos):
		var n := 5 if kinds[p.pos] == "diamond" else 1
		pickups[p.pos].queue_free()
		pickups.erase(p.pos)
		kinds[p.pos] = ""
		earn(p, n)


func _swing(t: float, mk: Node3D, a: Vector3, b: Vector3, pivot: Vector3, rider: Node3D, hold: Vector3) -> void:
	# A pendulum on the vine: the gorilla's hands follow an arc about the pivot
	# from grab point a to b. A rider, if any, is held against its chest.
	var va := a - pivot
	var vb := b - pivot
	var hands := pivot + va.normalized().slerp(vb.normalized(), t) * lerpf(va.length(), vb.length(), t)
	mk.position = hands - Vector3(0, 2.16, 0)
	if rider:
		rider.position = mk.position + hold


func banana_rescue(p: Dictionary) -> void:
	# The banana power-up. Just as a hit would finish the runner, a monkey
	# swings in on a vine, plucks them up and carries them forward to the next
	# safe slab, then sits and eats its banana. The swing is a real pendulum,
	# and the vine a simulated rope.
	p.banana -= 1
	var root: Node3D = p.a
	var i: int = p.pos
	var d: int = mini(i + 2, END - 1)
	while d < END - 1 and d < i + 6 and kinds[d] != "" and kinds[d] != "coin" and kinds[d] != "diamond":
		d += 1
	say("A gorilla swung in and carried %s to safety" % obj(p))
	announce("BANANA!", Color("ffe066"))
	slow_to = 0.6  # slowed, but the camera stays wide: a close-up would be all gorilla
	sfx.play("gorilla", 2.0)
	shake(0.3)
	root.scale = Vector3.ONE
	root.visible = true
	var from := root.position
	var to := spot(p, d)
	var ahead := Vector3(to.x - from.x, 0, to.z - from.z).normalized()
	var hold := ahead * 0.8 + Vector3(0, 0.3, 0)  # the runner is held in front of its chest
	var grab_a := from - hold + Vector3(0, 2.16, 0)  # where its hands are on the vine when it takes hold
	var grab_b := to - hold + Vector3(0, 2.16, 0)
	var span := Vector2(to.x - from.x, to.z - from.z).length()
	var pivot := (grab_a + grab_b) / 2.0 + Vector3(0, maxf(6.0, span * 0.8), 0)
	var mk: Node3D = Animals.build("gorilla", self)
	world.add_child(mk)
	mk.hang = true
	var reach := maxf(pivot.distance_to(grab_a), pivot.distance_to(grab_b))
	var vine := Strand.new(world, 12, reach * 1.02 / 12.0, Vector2(0.09, 0.09), mat(Color("4f8f3a")), pivot, (grab_b - pivot).normalized())
	var entry := {"vine": vine, "pivot": pivot, "mk": mk}
	rescues.append(entry)
	var fly := Vector3(from.x - to.x, 0, from.z - to.z)
	mk.rotation.y = atan2(-fly.x, -fly.z)
	_swing(1.0, mk, grab_a, grab_b, pivot, null, hold)
	root.look_up = true
	# swings in from ahead, down to the runner
	var tw := create_tween()
	tw.tween_method(_swing.bind(mk, grab_a, grab_b, pivot, null, hold), 1.0, 0.0, 0.95).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	root.look_up = false
	root.hang = true
	sfx.play("rope", -6.0)
	sfx.play("punch", -6.0, 0.7)
	burst(root.position + Vector3(0, 1.8, 0), Color("ffe066"), 10, 3.0)
	mk.rotation.y = atan2(fly.x, fly.z)
	root.rotation = Vector3(0, mk.rotation.y, 0)
	# and back the other way, carrying them clear
	var tw2 := create_tween()
	tw2.tween_method(_swing.bind(mk, grab_a, grab_b, pivot, root, hold), 0.0, 1.0, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw2.finished
	root.hang = false
	p.pos = d
	p.danger = false
	await hop(root, to, 0.2, 0.18)
	root.rotation = Vector3(0, yaws[d], 0)
	squash(root)
	sfx.play("land")
	collect(p)
	spot_off()
	# the monkey drops down beside them and eats its reward
	rescues.erase(entry)
	for mesh in vine.meshes:
		mesh.queue_free()
	mk.hang = false
	var seat: Vector3 = path[d] + Vector3(0.2, 0, -1.9).rotated(Vector3.UP, yaws[d])  # squats on the path just ahead
	mk.rotation.y = yaws[d] + PI
	await hop(mk, seat, 0.6, 0.35)
	shake(0.3)
	sfx.play("land", 0.0, 0.6)
	var fruit := box(mk, Vector3(0.08, 0.24, 0.08), Vector3(0.26, 0.92, -0.24), Color("ffe066"))
	fruit.rotation.z = 0.5
	mk.eat = true
	sfx.play("gorilla", -6.0, 1.1)
	refresh_ui()
	await wait(1.1)
	mk.eat = false
	fruit.queue_free()
	hop(mk, seat + Vector3(3.0, -5.0, 0).rotated(Vector3.UP, yaws[d]), 1.6, 0.5)
	mk.create_tween().tween_callback(mk.queue_free).set_delay(0.6)


func wound(p: Dictionary) -> void:
	# hurt runners need time to heal, and fight worse until they have
	p.wounded = HEAL_TURNS
	p.a.wounded = true
	refresh_ui()


func screen_flash(c: Color) -> void:
	flash_rect.color = c
	flash_rect.create_tween().tween_property(flash_rect, "color:a", 0.0, 0.5)


func hud_lose(p: Dictionary, icon_id: String) -> void:
	# The lost heart (or spent respawn) jumps out of the player's token, big,
	# shudders, then drops away and fades, while the token flashes.
	var k := players.find(p)
	var chip := chips[k]
	chip.pivot_offset = chip.size / 2.0
	chip.scale = Vector2(1.25, 1.25)
	chip.modulate = Color(2.0, 0.55, 0.55) if icon_id == "heart" else Color(0.6, 1.4, 2.0)
	var ct := chip.create_tween().set_parallel()
	ct.tween_property(chip, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ct.tween_property(chip, "modulate", Color.WHITE, 0.6)
	var spots: Array[Vector2] = [chip.global_position + Vector2(chip.size.x / 2.0, chip.size.y)]
	if k == 0:  # your own loss also shows on your stats plate
		spots.append(me_bar.global_position + Vector2(me_bar.size.x / 2.0, 0))
		me_bar.pivot_offset = me_bar.size / 2.0
		me_bar.scale = Vector2(1.2, 1.2)
		me_bar.create_tween().tween_property(me_bar, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var t := ui_tex(icon_id)
	if t == null:
		return
	for at in spots:
		var fx := TextureRect.new()
		fx.texture = t
		fx.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		fx.size = Vector2(96, 96)
		fx.pivot_offset = Vector2(48, 48)
		fx.position = at - Vector2(48, 30)
		fx.scale = Vector2(0.3, 0.3)
		fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flash_rect.get_parent().add_child(fx)
		var tw := fx.create_tween()
		tw.tween_property(fx, "scale", Vector2(1.5, 1.5), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		for s in 3:
			tw.tween_property(fx, "rotation", 0.35, 0.06)
			tw.tween_property(fx, "rotation", -0.35, 0.06)
		tw.tween_property(fx, "rotation", 0.9, 0.5)
		tw.parallel().tween_property(fx, "position:y", fx.position.y + 190.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(fx, "modulate", Color(0.5, 0.0, 0.0, 0.0) if icon_id == "heart" else Color(0.0, 0.3, 0.6, 0.0), 0.5)
		tw.tween_callback(fx.queue_free)


func hurt(p: Dictionary) -> String:
	# returns "blocked" (shield), "saved" (banana rescue), "hit" (lost a heart) or "gone" (respawned or out)
	if p.shield:
		p.shield = false
		sfx.play("good")
		popup(p.a.position, "BLOCKED!", Color("5fe0ff"))
		burst(p.a.position + Vector3(0, 1, 0), Color("5fe0ff"), 14, 4.0)
		refresh_ui()
		await wait(0.4)
		return "blocked"
	if p.hearts <= 1 and p.banana > 0:  # this hit would be the last: the banana calls in a rescue
		await banana_rescue(p)
		return "saved"
	p.hearts -= 1
	wound(p)
	sfx.play("bad")
	popup(p.a.position, "-1 LIFE", Color("ff6b5e"))
	p.a.flash()
	p.a.pose = "hit"
	p.a.express("pain", 1.0)
	burst(p.a.position + Vector3(0, 1.5, 0), Color("e2463a"), 18, 5.0)   # the lost heart shatters
	burst(p.a.position + Vector3(0, 1.5, 0), Color("ff9aa0"), 8, 3.0)
	hud_lose(p, "heart")
	if not p.bot:
		screen_flash(Color(1, 0.1, 0.05, 0.38))
	refresh_ui()
	await wait(0.55)
	p.a.pose = ""
	if p.hearts > 0:
		return "hit"
	var cp: int = (p.pos / 5) * 5
	if cp <= bo:
		cp = bo + 3
	await lose_all(p, mini(cp, END - 1))
	return "gone"


func die_anim(p: Dictionary) -> void:
	# Out of lives: stagger, spin, fall flat in a puff of dust; then a small
	# white soul lifts off and fades. Shown close up and slowed.
	var root: Node3D = p.a
	spotlight(p, 0.5)
	sfx.play("crush", -3.0)
	if root.scale.y > 0.5:  # (already flattened if the boulder did it)
		root.pose = "hit"
		var yaw := root.rotation.y
		var tw := root.create_tween()
		tw.tween_property(root, "rotation:y", yaw + TAU * 1.25, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(root, "rotation:x", PI / 2.0, 0.28).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		await tw.finished
		root.pose = ""
	shake(0.3)
	root.express("ko")
	burst(root.position + Vector3(0, 0.3, 0), Color("d8c9a0"), 22, 3.5)
	plume(root.position + Vector3(0, 0.2, 0), Color("5a5560"), 28, 2.4, 1.3)  # smoke rises off the fallen
	sfx.play("land", 0.0, 0.6)
	await wait(0.45)
	var soul := Node3D.new()
	soul.position = root.position + Vector3(0, 0.8, 0)
	world.add_child(soul)
	var white := Color("f4fbff")
	box(soul, Vector3(0.5, 0.6, 0.5), Vector3.ZERO, white).material_override = mat(white, true)
	box(soul, Vector3(0.38, 0.25, 0.38), Vector3(0, -0.4, 0), white).material_override = mat(white, true)
	for ex in [-0.12, 0.12]:
		box(soul, Vector3(0.09, 0.12, 0.05), Vector3(ex, 0.08, -0.26), Color("1a1410"))
	soul.rotation.y = cam_yaw
	soul.scale = Vector3.ONE * 0.6
	sfx.play("mystery", -6.0, 1.4)
	var st := soul.create_tween().set_parallel()
	st.tween_property(soul, "position:y", soul.position.y + 4.5, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	st.tween_property(soul, "scale", Vector3.ONE * 0.05, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	st.tween_property(soul, "rotation:y", cam_yaw + 0.6, 1.1)
	for k in 4:
		burst(soul.position + Vector3(0, k * 0.6, 0), white, 5, 1.5)
		await wait(0.2)
	root.visible = false
	await wait(0.3)
	soul.queue_free()
	spot_off()


func lose_all(p: Dictionary, at_slab: int) -> void:
	# No hearts left: die, then spend a respawn and return at the last torch, or leave the game.
	var root: Node3D = p.a
	await die_anim(p)
	if p.revives > 0:
		p.revives -= 1
		hud_lose(p, "ankh")
		say("%s ran out of lives. Respawns left: %d" % [subj(p), p.revives])
		if not p.bot:
			announce("RESPAWN USED", Color("5fe0ff"))
		refresh_ui()
		await wait(0.9)
		await reborn(p, at_slab)
		return
	p.out = true
	say("%s ran out of lives and respawns. Out of the game!" % subj(p))
	announce("%s OUT" % ("YOU ARE" if not p.bot else p.name), Color("ff6b5e"))
	if not p.bot:
		screen_flash(Color(0.6, 0, 0, 0.5))
	refresh_ui()
	await wait(1.4)


func reborn(p: Dictionary, at_slab: int) -> void:
	# Respawn: a beam of light strikes the slab, the player drops down inside
	# it with full lives, lands in a ring of sparks and cheers. Misses a turn.
	p.pos = at_slab
	p.hearts = 3
	p.skip = 1
	p.wounded = 0
	p.a.wounded = false
	var at := spot(p, p.pos)
	var root: Node3D = p.a
	root.visible = true
	root.scale = Vector3.ONE
	root.rotation = Vector3(0, yaws[p.pos], 0)
	root.position = at + Vector3(0, 11, 0)
	spotlight(p, 0.6)
	var gold := Color("fff3a8")
	var beam := box(world, Vector3(1.1, 34, 1.1), at + Vector3(0, 17, 0), gold)
	beam.material_override = mat(gold, true)
	beam.scale = Vector3(0.05, 1, 0.05)
	beam.create_tween().tween_property(beam, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	sfx.play("reborn")
	plume(at, Color("fff3a8"), 36, 6.0, 1.3, true)   # light streams up the beam
	plume(at, Color("7dff9b"), 14, 3.5, 1.3, true)
	root.express("")
	say("%s: reborn at slab %d" % [subj(p), p.pos])
	if not p.bot:
		screen_flash(Color(1, 0.97, 0.75, 0.4))
	await wait(0.3)
	root.air = true
	await hop(root, at, 0.0, 0.9)
	root.air = false
	squash(root)
	sfx.play("land")
	for k in 10:  # ring of sparks round the landing
		var ang := k * TAU / 10.0
		burst(at + Vector3(cos(ang) * 0.9, 0.2, sin(ang) * 0.9), gold, 4, 3.0)
	burst(at + Vector3(0, 1.0, 0), Color("7dff9b"), 20, 5.0)
	root.pose = "cheer"
	var tw := beam.create_tween()
	tw.tween_property(beam, "scale", Vector3(0.05, 1, 0.05), 0.5)
	tw.tween_callback(beam.queue_free)
	# hearts refill in the HUD with a bounce
	var chip := chips[players.find(p)]
	chip.pivot_offset = chip.size / 2.0
	chip.scale = Vector2(1.3, 1.3)
	chip.modulate = Color(1.6, 1.5, 0.8)
	var ct := chip.create_tween().set_parallel()
	ct.tween_property(chip, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ct.tween_property(chip, "modulate", Color.WHITE, 0.7)
	refresh_ui()
	await wait(0.7)
	root.pose = ""
	spot_off()


# ---- slab events

func rope_cross(p: Dictionary) -> void:
	# Step by step so it reads: walk over to the post, turn to face along the
	# rope, look up at it, crouch, spring up, catch it and hang for a beat.
	# Only then does the crossing start.
	var root: Node3D = p.a
	var from_i: int = p.pos
	var d: int = rope_to[from_i]
	var rope: Dictionary = ropes[from_i]
	var s: Strand = rope.s
	say("%s found a rope to slab %d" % [subj(p), d])
	spotlight(p, 0.7)
	var along: Vector3 = rope.b - rope.a
	var rope_yaw := atan2(-along.x, -along.z)
	var under: Vector3 = path[from_i] + Vector3(-0.78, 0, 0).rotated(Vector3.UP, yaws[from_i])  # just beside the post
	var to_post := under - root.position
	root.turn_to(atan2(-to_post.x, -to_post.z))
	root.run = true
	var walk := root.create_tween()
	walk.tween_property(root, "position", under, 0.4)
	await walk.finished
	root.run = false
	root.turn_to(rope_yaw)
	root.look_up = true
	await wait(0.4)
	root.pose = "crouch"
	await wait(0.28)
	root.pose = ""
	root.look_up = false
	popup(root.position, "+%d" % (d - from_i), Color("7dff9b"))
	await hop(root, s.point_at(0.05) - Vector3(0, 1.75, 0), 0.9, 0.42)
	root.hang = true
	root.rotation = Vector3(0, rope_yaw, 0)
	s.weigh(0.05, 0.35)  # the rope dips as it takes their weight
	sfx.play("rope", -4.0)
	burst(s.point_at(0.05), Color("d8b25a"), 6, 2.0)
	await wait(0.5)
	spot_off()
	say("%s crossed the rope to slab %d" % [subj(p), d])
	var dur: float = 0.9 + rope.a.distance_to(rope.b) * 0.08
	var tw := create_tween()
	tw.tween_method(_ride.bind(s, root), 0.05, 0.96, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	root.hang = false
	p.pos = d
	await hop(root, spot(p, d), 0.4, 0.25)
	root.rotation = Vector3(0, yaws[d], 0)
	squash(root)
	sfx.play("land")
	burst(root.position, Color("52d273"), 16, 4.0)


func snake_strike(p: Dictionary) -> void:
	var root: Node3D = p.a
	var i: int = p.pos
	var d: int = safe_back(p, snake_to[i])
	var cobra: Node3D = snakes[i].node
	var local: Vector3 = slabs[i].to_local(root.global_position)
	say("A cobra threw %s back to slab %d" % [obj(p), d])
	spotlight(p, 0.45)
	cobra.wake_to = 1.0
	cobra.aim = atan2(local.x, local.z + 0.12)  # turn its neck towards the runner
	sfx.play("snake")
	await wait(0.6)  # rears, sways, eyes its target
	var tw := cobra.create_tween()
	tw.tween_property(cobra, "strike", 1.0, 0.09)
	await tw.finished
	shake(0.35)
	sfx.play("bump")
	await hitstop(0.1)
	burst(root.position + Vector3(0, 1, 0), Color("b8e04a"), 18, 5.0)
	popup(root.position, "-%d" % (i - d), Color("ff6b5e"))
	wound(p)
	cobra.create_tween().tween_property(cobra, "strike", 0.0, 0.45)
	# thrown back: tumbles slab by slab down the path
	spot_off()
	root.air = true
	for k in range(i - 1, d - 1, -1):
		root.rotation.x -= 1.3
		await hop(root, spot(p, k), 0.5, 0.075)
		p.pos = k
		refresh_ui()
	root.air = false
	root.rotation = Vector3(0, yaws[d], 0)
	squash(root)
	sfx.play("land")
	burst(root.position, STONE.lightened(0.2), 10, 3.0)


func crumble(p: Dictionary) -> void:
	var root: Node3D = p.a
	var slab := slabs[p.pos]
	say("The floor crumbled under %s!" % obj(p))
	spotlight(p, 0.5)
	shake(0.4)
	sfx.play("crumble")
	burst(root.position, CRUMBLE, 24, 5.0)
	# slab blocks break off first, then the pillar collapses from the top down
	var parts: Array = []
	parts.append_array(slab.get_meta("blocks"))
	parts.append_array(slab.get_meta("shaft"))
	var homes: Array[Vector3] = []
	var tw := slab.create_tween().set_parallel()
	for k in parts.size():
		var b: MeshInstance3D = parts[k]
		homes.append(b.position)
		var delay := rng.randf_range(0.0, 0.25) if k < 9 else 0.25 + (k - 9) * 0.09
		var fall := b.position + Vector3(rng.randf_range(-1.6, 1.6), -7.5, rng.randf_range(-1.6, 1.6))
		var spin := Vector3(rng.randf_range(-4, 4), rng.randf_range(-4, 4), rng.randf_range(-4, 4))
		tw.tween_property(b, "position", fall, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(delay)
		tw.tween_property(b, "rotation", spin, 0.75).set_delay(delay)
		tw.tween_property(b, "scale", Vector3.ONE * 0.01, 0.2).set_delay(delay + 0.6)
	root.air = true
	tw.tween_property(root, "position:y", root.position.y - 7.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(0.25)
	await tw.finished
	spot_off()
	burst(root.position, Color("d8c9a0"), 22, 4.0)  # dust where it all hits the ground
	sfx.play("land", 0.0, 0.7)
	rebuild(slab, parts, homes)
	p.pos = safe_back(p, p.pos - 1)
	root.position = spot(p, p.pos) + Vector3(0, 7, 0)
	await hop(root, spot(p, p.pos), 0.0, 0.4)
	root.air = false
	squash(root)
	await hurt(p)


func rebuild(slab: Node3D, parts: Array, homes: Array[Vector3]) -> void:
	# The pillar grows back from the ground up, then the slab blocks spiral in
	# one by one, each landing with a click, and a last flash seals it.
	await wait(1.0)
	if not is_instance_valid(slab):
		return
	var order: Array[int] = [13, 12, 11, 10, 9, 0, 1, 2, 5, 8, 7, 6, 3, 4]
	var tw := slab.create_tween().set_parallel()
	for n in order.size():
		var k := order[n]
		var b: MeshInstance3D = parts[k]
		var delay := n * 0.08
		var ang := n * 1.1
		b.position = homes[k] + (Vector3(0, -6, 0) if k >= 9 else Vector3(cos(ang) * 2.4, -2.5, sin(ang) * 2.4))
		b.rotation = Vector3(ang, ang * 0.7, 0)
		tw.tween_property(b, "scale", Vector3.ONE, 0.15).set_delay(delay)
		tw.tween_property(b, "position", homes[k], 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
		tw.tween_property(b, "rotation", Vector3.ZERO, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)
		tw.tween_callback(sfx.play.bind("step", -12.0, 1.2 + n * 0.05)).set_delay(delay + 0.38)
	await tw.finished
	if is_instance_valid(slab):
		burst(slab.position + Vector3(0, 0.6, 0), Color("fff3a8"), 14, 3.0)
		sfx.play("good", -12.0)


func _carry(t: float, a: Node3D, root: Node3D, from: Vector3, to: Vector3) -> void:
	a.position = from.lerp(to, t) + Vector3(0, sin(t * PI) * 0.12, 0)
	root.position = a.position + Vector3(0, 2.5, 0)


func _circle(ang: float, a: Node3D, root: Node3D) -> void:
	a.position = root.position + Vector3(cos(ang) * 0.9, 2.4 + sin(ang * 2.0) * 0.2, sin(ang) * 0.9)
	a.rotation.y = -ang


func mystery(p: Dictionary) -> void:
	# "?" slab: an animal helps or robs you, or a chest holds a power-up.
	var root: Node3D = p.a
	var i: int = p.pos
	say("Something moves in the jungle...")
	spotlight(p, 0.8)
	sfx.play("mystery")
	burst(root.position + Vector3(0, 1, 0), MYSTERY.lightened(0.3), 22, 5.0)
	await wait(0.6)
	var kind: String = ["elephant", "parrot", "monkey", "chest", "chest"][rng.randi_range(0, 4)]
	var a: Node3D = Animals.build(kind, self)
	world.add_child(a)
	a.position = path[i]
	a.rotation.y = yaws[i]
	a.scale = Vector3.ONE * 0.01
	a.create_tween().tween_property(a, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	match kind:
		"elephant":
			var d: int = mini(i + 4, END - 1)
			say("A temple elephant carried %s ahead to slab %d" % [obj(p), d])
			announce("+%d SLABS" % (d - i), Color("7dff9b"))
			sfx.play("trumpet")
			a.roar = 1.2  # trunk up as it trumpets
			await hop(root, path[i] + Vector3(0, 2.5, 0), 1.9, 0.5)
			spot_off()
			for k in range(i + 1, d + 1):
				a.rotation.y = yaws[k - 1]
				root.rotation.y = yaws[k - 1]
				var tw := create_tween()
				tw.tween_method(_carry.bind(a, root, a.position, path[k]), 0.0, 1.0, 0.3)
				await tw.finished
				shake(0.1)
				sfx.play("land", -6.0, 0.6)
				burst(path[k], STONE.lightened(0.2), 6, 2.0)
				p.pos = k
				collect(p)
			await hop(root, spot(p, d), 0.9, 0.35)
		"parrot":
			say("A parrot brought %s a diamond: +5 coins" % obj(p))
			sfx.play("chirp", 0.0, 0.8)
			var tw := create_tween()
			tw.tween_method(_circle.bind(a, root), 0.0, TAU * 2.0, 1.2)
			await tw.finished
			await reward(p, "coin", "+5 COINS", GOLD)
			earn(p, 5)
		"monkey":
			a.position = path[i] + Vector3(0, 0, -0.9).rotated(Vector3.UP, yaws[i])
			a.rotation.y = yaws[i] + PI
			sfx.play("monkey")
			for k in 2:
				await hop(a, a.position, 0.7, 0.25)
			if p.coins > 0:
				var lost: int = mini(4, p.coins)
				p.coins -= lost
				say("A monkey stole %d coins from %s" % [lost, obj(p)])
				announce("-%d COINS" % lost, Color("ff6b5e"))
				burst(root.position + Vector3(0, 1, 0), GOLD, 10, 4.0)
				sfx.play("bad", -4.0)
				refresh_ui()
			else:
				say("A monkey threw a coconut at %s" % obj(p))
				await hurt(p)
			await wait(0.3)
		"chest":
			a.position = path[i] + Vector3(0, 0, -0.75).rotated(Vector3.UP, yaws[i])
			a.rotation.y = yaws[i] + PI
			await wait(0.35)
			var lid: Node3D = a.get_meta("lid")
			lid.create_tween().tween_property(lid, "rotation:x", 1.9, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			sfx.play("good")
			burst(a.position + Vector3(0, 0.8, 0), GOLD, 24, 5.0)
			var prize := rng.randi_range(0, 2)
			if rng.randf() < 0.13 and p.banana == 0:  # rare
				prize = 9
			if prize == 9:
				p.banana = 1
				say("%s found a chest: a banana! A gorilla will save you once" % subj(p))
				await reward(p, "banana", "BANANA!", Color("ffe066"))
			elif prize == 0 and p.revives < 3:
				p.revives += 1
				say("%s found a chest: one extra respawn" % subj(p))
				await reward(p, "ankh", "+1 RESPAWN", Color("5fe0ff"))
			elif prize == 1 and not p.shield:
				p.shield = true
				say("%s found a chest: a shield that blocks the next hit" % subj(p))
				await reward(p, "shield", "SHIELD", Color("5fe0ff"))
			elif p.hearts < 5:
				p.hearts += 1
				say("%s found a chest: one extra life" % subj(p))
				await reward(p, "heart", "+1 LIFE", Color("7dff9b"))
			else:
				say("%s found a chest: +5 coins" % subj(p))
				await reward(p, "coin", "+5 COINS", GOLD)
				earn(p, 5)
			refresh_ui()
			await wait(0.3)
	spot_off()
	var out := a.create_tween()
	out.tween_property(a, "scale", Vector3.ONE * 0.01, 0.25)
	out.tween_callback(a.queue_free)


func subj(p: Dictionary) -> String:
	return p.name if p.bot else "You"


func obj(p: Dictionary) -> String:
	return p.name if p.bot else "you"


func announce(text: String, c: Color) -> void:
	# big centre-screen banner for rewards and major events
	lbl_big.text = text
	lbl_big.add_theme_color_override("font_color", c)
	lbl_big.modulate.a = 1.0
	lbl_big.scale = Vector2(0.4, 0.4)
	if big_tw:
		big_tw.kill()
	big_tw = lbl_big.create_tween()
	big_tw.tween_property(lbl_big, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	big_tw.tween_interval(1.1)
	big_tw.tween_property(lbl_big, "modulate:a", 0.0, 0.35)


func note(text: String) -> void:
	# quiet line for weather and time of day; never overwrites the game message
	lbl_note.text = text
	lbl_note.modulate.a = 1.0
	if note_tw:
		note_tw.kill()
	note_tw = lbl_note.create_tween()
	note_tw.tween_interval(3.0)
	note_tw.tween_property(lbl_note, "modulate:a", 0.0, 0.8)


func stars(node: Node3D) -> void:
	var ring := Node3D.new()
	ring.position = Vector3(0, 2.15, 0)
	node.add_child(ring)
	for k in 3:
		box(ring, Vector3.ONE * 0.15, Vector3(cos(k * TAU / 3.0) * 0.42, 0, sin(k * TAU / 3.0) * 0.42), Color("ffe066")).material_override = mat(Color("ffe066"), true)
	var tw := ring.create_tween()
	tw.tween_property(ring, "rotation:y", TAU * 2.0, 1.1)
	tw.tween_callback(ring.queue_free)


func _drag(t: float, tg: Node3D, root: Node3D, from: Vector3, to: Vector3) -> void:
	tg.position = from.lerp(to, t) + Vector3(0, sin(t * PI) * 0.3, 0)
	root.position = tg.position + tg.global_basis * Vector3(0, 0.7, -1.25)


func tiger_attack(p: Dictionary) -> void:
	# Ambush. Leaves shake and something growls; the tiger leaps up out of the
	# forest and lands low on the slab; it stalks, rears up and roars, rakes
	# with a paw, and the runner bolts back down the path with it bounding
	# after. Then it pulls up, snarls once more and is gone.
	var root: Node3D = p.a
	var i: int = p.pos
	var side := dirs[i].cross(Vector3.UP) * (1.0 if rng.randf() < 0.5 else -1.0)
	var lair := path[i] + side * 7.0 + Vector3(0, -6.0, 0)
	say("Something is stalking %s..." % obj(p))
	sfx.play("growl", -2.0)
	for k in 3:
		burst(path[i] + side * (3.0 + k) + Vector3(0, -2.5, 0), Color("3c9140"), 14, 5.0)
		await wait(0.25)
	var tg: Node3D = Animals.build("tiger", self)
	world.add_child(tg)
	tg.position = lair
	var perch := path[i] + side * 1.05
	tg.look_at(Vector3(perch.x, lair.y, perch.z))
	spotlight(p, 0.45)
	await hop(tg, perch, 3.6, 0.65)
	# lands in a crouch, facing its prey, who spins round to face it
	tg.crouch = 1.0
	shake(0.4)
	sfx.play("land", 0.0, 0.6)
	burst(tg.position, STONE.lightened(0.2), 12, 3.0)
	tg.look_at(Vector3(root.position.x, tg.position.y, root.position.z))
	root.look_at(Vector3(tg.position.x, root.position.y, tg.position.z))
	root.pose = "guard"
	await wait(0.55)
	# rears up and roars
	tg.create_tween().tween_property(tg, "crouch", 0.0, 0.15)
	tg.roar = 2.2
	sfx.play("roar", 2.0)
	shake(0.5)
	popup(tg.position, "ROAR!", Color("ffb347"))
	root.pose = "hit"
	await wait(0.7)
	# one raking swipe of the paw
	var sw := tg.create_tween()
	sw.tween_property(tg, "swipe", 1.0, 0.22)
	sw.tween_property(tg, "swipe", 0.0, 0.01)
	await wait(0.12)
	sfx.play("punch")
	await hitstop(0.1)
	burst(root.position + Vector3(0, 1, 0), Color("f08a24"), 18, 5.0)
	root.pose = ""
	var res: String = await hurt(p)
	spot_off()
	if res == "hit" and p.pos == i:
		var d: int = safe_back(p, i - 4)
		say("%s fled from the tiger, back to slab %d" % [subj(p), d])
		announce("-%d SLABS" % (i - d), Color("ff6b5e"))
		root.run = true
		for k in range(i - 1, d - 1, -1):
			root.turn_to(yaws[k] + PI)
			# the tiger bounds along one slab behind
			var chase_to: Vector3 = path[k + 1]
			tg.look_at(Vector3(path[k].x, tg.position.y, path[k].z))
			tg.create_tween().tween_property(tg, "position", chase_to, 0.2)
			await hop(root, spot(p, k), 0.15, 0.2)
			sfx.play("step", -6.0)
			p.pos = k
			refresh_ui()
		root.run = false
		root.turn_to(yaws[d])
		tg.roar = 1.4  # pulls up and snarls after them
		sfx.play("growl", -4.0)
		await wait(0.6)
	var away := tg.position + side * 7.0 + Vector3(0, -6.0, 0)
	tg.look_at(Vector3(away.x, tg.position.y, away.z))
	await hop(tg, away, 2.6, 0.5)
	burst(away + Vector3(0, 2.5, 0), Color("3c9140"), 14, 4.0)
	tg.queue_free()


func update_sky(delta: float) -> void:
	# day cycle: blend the two nearest keys of DAY
	tod = fmod(tod + delta / 300.0, 1.0)
	var a: Dictionary = DAY[0]
	var b: Dictionary = DAY[1]
	for k in DAY.size() - 1:
		if tod >= DAY[k].at and tod <= DAY[k + 1].at:
			a = DAY[k]
			b = DAY[k + 1]
	var f := smoothstep(0.0, 1.0, (tod - a.at) / (b.at - a.at))
	rain_k = move_toward(rain_k, 1.0 if rain else 0.0, delta * 0.25)
	flash = maxf(0.0, flash - delta * 4.0)
	night_k = lerpf(a.night, b.night, f)
	var grey := Color("55606e")
	var top := Color(a.top).lerp(Color(b.top), f).lerp(grey.darkened(0.35), rain_k * 0.65)
	var hor := Color(a.hor).lerp(Color(b.hor), f).lerp(grey, rain_k * 0.65)
	var sun_c := Color(a.sun).lerp(Color(b.sun), f)
	sky_mat.set_shader_parameter("top", top)
	sky_mat.set_shader_parameter("horizon", hor)
	sky_mat.set_shader_parameter("sun_col", sun_c * (1.0 - rain_k))
	sky_mat.set_shader_parameter("cloud_lit", Color(a.lit).lerp(Color(b.lit), f).lerp(grey.lightened(0.25), rain_k * 0.8))
	sky_mat.set_shader_parameter("cloud_dark", Color(a.dark).lerp(Color(b.dark), f).lerp(grey.darkened(0.2), rain_k * 0.8))
	sky_mat.set_shader_parameter("coverage", lerpf(0.5, 0.92, rain_k))
	sky_mat.set_shader_parameter("stars", night_k * (1.0 - rain_k))
	sky_mat.set_shader_parameter("flash", flash * 0.6)
	env.fog_light_color = hor.lerp(top, 0.3)
	env.fog_density = 0.0011 * (1.0 + rain_k * 2.5)
	env.fog_height = cam_base.y - 7.0  # mist pools in the valley below whoever is on screen
	env.fog_height_density = 0.045
	env.ambient_light_color = Color(a.amb).lerp(Color(b.amb), f)
	env.ambient_light_energy = lerpf(a.amb_e, b.amb_e, f) * (1.0 - rain_k * 0.25) + flash * 2.5
	sun.light_color = sun_c
	sun.light_energy = lerpf(a.sun_e, b.sun_e, f) * (1.0 - rain_k * 0.55)
	sun.rotation_degrees = Vector3(lerpf(a.pitch, b.pitch, f), lerpf(a.yaw, b.yaw, f), 0)
	if is_instance_valid(nature) and nature.mist_mat:
		nature.mist_mat.set_shader_parameter("tint", hor.lerp(Color.WHITE, 0.6).darkened(night_k * 0.45))
		nature.mist_mat.set_shader_parameter("amount", 0.26 + rain_k * 0.3)
	rain_fx.emitting = rain_k > 0.05
	sfx.set_rain(rain_k)
	sfx.set_night(night_k)

	# weather turns now and then; thunder while it pours
	weather_in -= delta
	if weather_in <= 0.0:
		weather_in = rng.randf_range(35, 70)
		var before := rain
		rain = rng.randf() < 0.4
		if rain != before:
			note("Rain rolls in over the forest" if rain else "The rain clears")
	if rain_k > 0.6:
		thunder_in -= delta
		if thunder_in <= 0.0:
			thunder_in = rng.randf_range(6, 14)
			flash = 1.0
			sfx.play("thunder", -2.0)
	var dark := night_k > 0.4
	if dark != was_night:
		was_night = dark
		note("Night falls. Torches out!" if dark else "Dawn breaks over the temple")
	for p in players:
		p.a.night = dark


func bump(p: Dictionary) -> void:
	if p.pos <= 5:  # start zone is safe
		return
	for q in players:
		if q != p and active(q) and q.pos == p.pos:
			await fight(p, q)


func fight_odds(p: Dictionary, q: Dictionary) -> float:
	# Chance that the newcomer p beats the defender q. The newcomer has the edge
	# of surprise; wounds and lost hearts tell against either side.
	var c := 0.6
	if p.wounded > 0:
		c -= 0.25
	if q.wounded > 0:
		c += 0.25
	c += 0.05 * (p.hearts - q.hearts)
	return clampf(c, 0.15, 0.9)


func fight(p: Dictionary, q: Dictionary) -> void:
	# Two players on one slab. The outcome is decided by the odds, then played
	# out: square up, trade blows, scuffle in a dust cloud, and the winner kicks
	# the loser off the slab. The newcomer can lose.
	var chance := fight_odds(p, q)
	var p_wins := rng.randf() < chance
	var win: Dictionary = p if p_wins else q
	var lose: Dictionary = q if p_wins else p
	var a: Node3D = p.a
	var b: Node3D = q.a
	var wn: Node3D = win.a
	var ln: Node3D = lose.a
	var pct := roundi(chance * 100.0)
	say("%s %d%%  vs  %s %d%%" % ["YOU" if not p.bot else p.name, pct, "YOU" if not q.bot else q.name, 100 - pct])
	announce("FIGHT!", Color("ff6b5e"))
	sfx.play("gong", -2.0)
	a.look_at(Vector3(b.position.x, a.position.y, b.position.z))
	b.look_at(Vector3(a.position.x, b.position.y, a.position.z))
	var homes := {a: a.position, b: b.position}
	var mid := (a.position + b.position) / 2.0
	a.pose = "guard"
	b.pose = "guard"
	a.express("angry")
	b.express("angry")
	spotlight(p, 0.7)
	await wait(0.55)
	# exchanges: the loser lands one too, so the result is not obvious at once
	var rounds := [[ln, wn, "punch", "POW!"], [wn, ln, "punch", "BAM!"], [wn, ln, "kick", "WHACK!"]]
	for r in rounds:
		var att: Node3D = r[0]
		var vic: Node3D = r[1]
		var from := att.position
		att.pose = r[2]
		sfx.play("whoosh", -4.0)
		var lunge := att.create_tween()
		lunge.tween_property(att, "position", from.lerp(vic.position, 0.45), 0.09)
		await lunge.finished
		if r[2] == "kick":
			sfx.play("kick", 1.0)
		else:
			sfx.hit()
		sfx.play("oof", -5.0, rng.randf_range(0.85, 1.2))
		shake(0.22)
		vic.pose = "hit"
		vic.express("pain")
		att.express("angry")
		burst(vic.position + Vector3(0, 1.1, 0), Color("fff8e1"), 9, 4.5)
		burst(vic.position + Vector3(0, 1.5, 0), Color("ffe066"), 7, 6.0)  # comic stars
		popup(vic.position, r[3], Color("ffe066"))
		await hitstop(0.06)
		att.create_tween().tween_property(att, "position", from, 0.14)
		await wait(0.24)
		att.pose = "guard"
		vic.pose = "guard"
	for k in 4:  # the scuffle
		burst(mid + Vector3(rng.randf_range(-0.4, 0.4), 0.8, rng.randf_range(-0.4, 0.4)), Color("efe6cf"), 12, 3.5)
		sfx.hit()
		if k % 2 == 0:
			sfx.play("whoosh", -8.0)
		shake(0.15)
		wn.pose = "punch" if k % 2 == 0 else "kick"
		ln.pose = "hit" if k % 2 == 0 else "punch"
		await wait(0.11)
	wn.pose = "kick"
	ln.pose = "hit"
	ln.express("ko", 2.4)
	wn.express("angry")
	burst(mid + Vector3(0, 1.2, 0), Color("ffe066"), 20, 7.0)
	shake(0.45)
	popup(mid, "K.O.!", Color("ff6b5e"))
	sfx.play("ko", 3.0)
	sfx.play("oof", 0.0, 0.7)
	slow_to = 0.3  # the knockout plays in deep slow motion
	await hitstop(0.12)
	lose.pos = safe_back(lose, lose.pos - 1)
	ln.create_tween().tween_property(ln, "rotation:x", ln.rotation.x - TAU, 0.5)
	await hop(ln, spot(lose, lose.pos), 1.8, 0.5)
	spot_off()
	wn.pose = "cheer"
	wn.express("happy", 1.4)
	ln.pose = ""
	ln.rotation = Vector3(0, yaws[lose.pos], 0)
	squash(ln)
	sfx.play("bodyfall", 0.0)
	stars(ln)
	say("%s won the fight" % subj(win))
	await wait(0.6)
	wn.pose = ""
	wn.position = homes[wn]
	wn.rotation = Vector3(0, yaws[win.pos], 0)
	var landed: int = lose.pos
	await hurt(lose)
	if active(lose) and lose.pos == landed:
		await settle(lose, true)


func boulder_turn() -> void:
	# The boulder chases whoever is last. It is never a surprise: when it is
	# anywhere near, the camera swings round to watch it roll, and it must
	# catch a runner twice running (a close call, then the crush) to kill.
	var last: Dictionary = {}
	for p in players:
		if active(p) and (last.is_empty() or p.pos < last.pos):
			last = p
	if last.is_empty():
		return
	if round_no < 4:  # grace: boulder sleeps while everyone leaves the start
		if round_no == 3:
			say("The boulder is waking up...")
			await wait(0.8)
		return
	# The boulder only ever rolls forward. A runner who has somehow ended up at
	# or behind it scrambles clear to just ahead of it instead.
	for p in players:
		if active(p) and p.pos <= bo + 1:
			focus_p = p
			p.pos = mini(bo + 3, END - 1)
			p.danger = false
			say("%s scrambled clear of the boulder" % subj(p))
			await hop(p.a, spot(p, p.pos), 1.4, 0.5)
			p.a.rotation = Vector3(0, yaws[p.pos], 0)
			refresh_ui()
	last = {}
	for p in players:
		if active(p) and (last.is_empty() or p.pos < last.pos):
			last = p
	focus_p = last
	var speed := mini(2 + round_no / 6, 4)
	if last.pos - bo > 12:
		speed += 2
	var from_i := bo
	var caught: bool = bo + speed >= last.pos
	var crushed: bool = caught and last.danger
	if crushed:
		bo = maxi(bo, last.pos)
	elif caught:
		bo = maxi(bo, last.pos - 3)
	else:
		bo += speed
	var near: bool = last.pos - bo <= 9
	if near:  # look back down the path at it
		var i: int = clampi(last.pos, 0, END)
		in_cine = true
		cine_smooth = 5.0
		cine_target = boulder
		cine_pos = last.a.position + dirs[i] * 5.5 + dirs[i].cross(Vector3.UP) * 2.6 + Vector3(0, 4.2, 0)
		cine_look_now = last.a.position + Vector3(0, 1.0, 0)
		announce("BOULDER!", Color("ff9a2e"))
		last.a.express("scared")
		last.a.turn_to(yaws[i] + PI)  # the runner looks back at it
		await wait(0.55)
	shake(0.2)
	sfx.play("boulder")
	var dur := 0.7 + (0.5 if near else 0.0)
	var tw := create_tween()
	tw.tween_method(func(f: float) -> void:
		var a := floori(f)
		boulder.position = slab_pos(a).lerp(slab_pos(a + 1), f - a) + Vector3(0, 1.25, 0)
		if near and Engine.get_frames_drawn() % 4 == 0:
			burst(boulder.position - Vector3(0, 1.1, 0), Color("b3ada1"), 3, 2.5), float(from_i), float(bo), dur)
	await tw.finished
	burst(boulder.position - Vector3(0, 1.2, 0), Color("8a8478"), 14, 4.0)
	for p in players:
		p.danger = false
	if crushed and last.banana > 0:  # snatched from under the boulder
		_end_watch(last)
		await banana_rescue(last)
	elif crushed:
		last.a.scale = Vector3(1.3, 0.12, 1.3)
		last.a.express("ko")
		shake(0.7)
		sfx.play("crush")
		await hitstop(0.12)
		burst(boulder.position, last.color, 30, 7.0)
		say("The boulder crushed %s!" % obj(last))
		await wait(0.9)
		_end_watch(last)
		last.hearts = 0
		await lose_all(last, mini(bo + 3, END - 1))
	elif caught:
		last.danger = true  # only a close call arms the crush
		shake(0.4)
		sfx.play("bad", -4.0)
		popup(last.a.position, "CLOSE!", Color("ff6b5e"))
		show_card("", "CLOSE CALL!", "%s must get clear, or be crushed next time" % ("YOU" if not last.bot else last.name), Color("ff5a4a"), 1.4)
		say("Close call for %s! Boulder right behind" % obj(last))
		await wait(0.9)
	else:
		say("Boulder is %d slabs behind %s" % [last.pos - bo, obj(last)])
	_end_watch(last)
	refresh_ui()
	await wait(0.6)


func _end_watch(last: Dictionary) -> void:
	if not in_cine:
		return
	in_cine = false
	cine_target = null
	cine_smooth = 0.0
	if active(last):
		last.a.express("")
		last.a.turn_to(yaws[clampi(last.pos, 0, END)])


func title(parent: Node, text: String, size: int, c: Color) -> Label:
	var l := _label(size)
	l.text = text
	l.add_theme_color_override("font_color", c)
	l.add_theme_constant_override("outline_size", maxi(6, size / 5))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", maxi(2, size / 12))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func menu_button(parent: Node, text: String, c: Color, cb: Callable, enabled := true, size := 38) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(0, 104)
	b.add_theme_font_override("font", ui_font)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_constant_override("outline_size", 10)
	b.add_theme_color_override("font_outline_color", Color("3a2410"))
	for n in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(n, Color("fffbe8"))
	b.add_theme_color_override("font_disabled_color", Color("a59c8c"))
	b.add_theme_stylebox_override("normal", _btn_style(c, false))
	b.add_theme_stylebox_override("hover", _btn_style(c.lightened(0.1), false))
	b.add_theme_stylebox_override("pressed", _btn_style(c.darkened(0.12), true))
	b.add_theme_stylebox_override("disabled", _btn_style(Color("4a443c"), true))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if enabled:
		b.pressed.connect(func() -> void: sfx.play("step"))
		b.pressed.connect(cb)
	parent.add_child(b)
	return b


func icon_button(drawer: Callable, cb: Callable, right: bool, row := 0) -> void:
	# round corner button with a drawn icon (gear, back arrow)
	var b := Button.new()
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT if right else Control.PRESET_TOP_LEFT)
	b.offset_left = -130.0 if right else 34.0
	b.offset_right = -34.0 if right else 130.0
	b.offset_top = 60 + row * 112
	b.offset_bottom = 156 + row * 112
	var st := _round(Color("6b4a2c"), 48, 5, Color("ffd76a"))
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", _round(Color("83603c"), 48, 5, Color("ffd76a")))
	b.add_theme_stylebox_override("pressed", _round(Color("52381f"), 48, 5, Color("c98a1e")))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.draw.connect(drawer.bind(b))
	b.pressed.connect(func() -> void: sfx.play("step"))
	b.pressed.connect(cb)
	lobby.add_child(b)


func _draw_gear(b: Control) -> void:
	var c := b.size / 2.0
	var r := b.size.x * 0.24
	var col := Color("fff3c4")
	for k in 8:
		b.draw_set_transform(c, k * TAU / 8.0, Vector2.ONE)
		b.draw_rect(Rect2(-r * 0.24, -r * 1.42, r * 0.48, r * 0.62), col)
	b.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	b.draw_circle(c, r, col)
	b.draw_circle(c, r * 0.42, Color("6b4a2c"))


func _draw_trophy(b: Control) -> void:
	var t := ui_tex("trophy")
	if t:
		b.draw_texture_rect(t, Rect2(b.size * 0.2, b.size * 0.6), false)
	else:
		b.draw_string(ui_font, Vector2(0, b.size.y * 0.5 + 16), "#1", HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 40, Color("fff3c4"))


func _draw_help(b: Control) -> void:
	b.draw_string(ui_font, Vector2(0, b.size.y * 0.5 + 22), "?", HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 60, Color("fff3c4"))


func _draw_back(b: Control) -> void:
	var c := b.size / 2.0
	var r := b.size.x * 0.22
	var col := Color("fff3c4")
	b.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.1, 0), c + Vector2(r * 0.5, -r * 1.1), c + Vector2(r * 0.5, r * 1.1)]), col)


func _draw_soon(b: Control) -> void:
	# little red "SOON" tag pinned to a disabled button
	var r := Rect2(b.size.x - 150, -16, 130, 46)
	b.draw_style_box(_round(Color("d6402e"), 12, 4, Color("fff3c4")), r)
	b.draw_string(ui_font, r.position + Vector2(0, 33), "SOON", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 26, Color("fffbe8"))


func _draw_card(b: Control, n: int) -> void:
	# bot-count card: one little face per rival under the number
	var w := 30.0
	var x0 := b.size.x / 2.0 - (n * w + (n - 1) * 6.0) / 2.0
	for k in n:
		var c: Color = ROSTER[k + 1].color
		var at := Vector2(x0 + k * (w + 6.0), b.size.y - 62.0)
		b.draw_rect(Rect2(at - Vector2(3, 3), Vector2(w + 6, w + 6)), Color("2a2118"))
		b.draw_rect(Rect2(at, Vector2(w, w)), c)
		b.draw_rect(Rect2(at + Vector2(5, 11), Vector2(w - 10, w - 14)), Color("c68e5f"))
		b.draw_rect(Rect2(at + Vector2(1, 6), Vector2(w - 2, 6)), Color("b08d57"))


func show_lobby() -> void:
	in_lobby = true
	results.visible = false
	for n in hud_nodes:
		n.visible = false
	menu("main")


func menu(page: String) -> void:
	for c in lobby.get_children():
		c.queue_free()
	lobby.visible = true
	var cream := Color("fff3c4")
	var wood := Color("6b4a2c")
	var orange := Color("ee8a1c")
	var green := Color("3fae5a")

	var shade_rect := ColorRect.new()  # dims the scene so the menu reads clearly
	shade_rect.color = Color(0.05, 0.03, 0.02, 0.38)
	shade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade_rect.offset_top = -400    # spills past the safe inset so the whole screen dims
	shade_rect.offset_bottom = 400
	shade_rect.offset_left = -3000
	shade_rect.offset_right = 3000
	shade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lobby.add_child(shade_rect)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 46
	col.offset_right = -46
	col.offset_top = 150
	col.offset_bottom = -70
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 26)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lobby.add_child(col)

	if page == "main":
		if ResourceLoader.exists("res://ui/logo.png"):
			var logo := TextureRect.new()
			logo.texture = load("res://ui/logo.png")
			logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			logo.custom_minimum_size = Vector2(0, 430)
			logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(logo)
		else:
			title(col, "TREASURE\nSEEKER", 104, GOLD)
		title(col, "Race through the jungle to the temple gold", 26, cream)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _tablet())
	col.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	panel.add_child(v)

	match page:
		"main":
			menu_button(v, "PLAY", orange, menu.bind("bots"), true, 52).custom_minimum_size = Vector2(0, 132)
			var mp := menu_button(v, "MULTIPLAYER", wood, menu.bind("main"), false)
			mp.draw.connect(_draw_soon.bind(mp))
			menu_button(v, "POWER-UPS", wood, menu.bind("shop"))
			icon_button(_draw_gear, menu.bind("settings"), true)
			icon_button(_draw_help, menu.bind("help"), false)
			icon_button(_draw_trophy, menu.bind("ranks"), true, 1)
		"bots":
			title(v, "CHOOSE YOUR RIVALS", 46, GOLD)
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 26)
			v.add_child(row)
			_key(menu_button(row, "-", wood, step_bots.bind(-1), bot_count > 1, 70))
			var num := title(row, str(bot_count), 130, cream)
			num.autowrap_mode = TextServer.AUTOWRAP_OFF
			num.custom_minimum_size = Vector2(150, 0)
			_key(menu_button(row, "+", wood, step_bots.bind(1), bot_count < 5, 70))
			var faces := Control.new()
			faces.custom_minimum_size = Vector2(0, 52)
			faces.mouse_filter = Control.MOUSE_FILTER_IGNORE
			faces.draw.connect(_draw_faces.bind(faces))
			v.add_child(faces)
			title(v, "%d bot%s will race you" % [bot_count, "" if bot_count == 1 else "s"], 26, cream)
			menu_button(v, "START RACE", orange, begin_picked, true, 48).custom_minimum_size = Vector2(0, 124)
			icon_button(_draw_back, menu.bind("main"), false)
		"help":
			title(v, "HOW TO PLAY", 50, GOLD)
			title(v, "Roll the die. First to the temple gate wins. Stay ahead of the boulder.", 22, cream)
			var rules := [["s_rope", "ROPE", "Swing far ahead"], ["s_snake", "COBRA", "Thrown far back"], ["s_tiger", "TIGER", "Eyes in the bush: lose a life, flee back 4"], ["s_spike", "SPIKES", "Tap in time to jump, or lose a life"], ["s_crumble", "CRACKED SLAB", "You fall and lose a life"], ["s_mystery", "MYSTERY", "An animal or a treasure chest"], ["heart", "3 LIVES", "Lose them all: use a respawn"], ["heart_empty", "WOUNDED", "After any hit: weaker in fights for 2 turns"], ["ankh", "2 RESPAWNS", "None left: you are out"], ["banana", "BANANA (RARE)", "A gorilla carries you clear of a fatal hit"]]
			for g in rules:
				var line := HBoxContainer.new()
				line.add_theme_constant_override("separation", 14)
				v.add_child(line)
				var pic := TextureRect.new()
				pic.texture = ui_tex(g[0])
				pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				pic.custom_minimum_size = Vector2(60, 60)
				line.add_child(pic)
				var words := VBoxContainer.new()
				words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				words.add_theme_constant_override("separation", -6)
				line.add_child(words)
				title(words, g[1], 25, cream).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
				title(words, g[2], 19, Color("c9b98a")).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			v.add_theme_constant_override("separation", 8)
			icon_button(_draw_back, menu.bind("main"), false)
		"ranks":
			title(v, "LEADERBOARD", 50, GOLD)
			var races := int(stats.races)
			var wins := int(stats.wins)
			title(v, "Races %d   Wins %d   Win rate %d%%" % [races, wins, (wins * 100 / races) if races > 0 else 0], 24, cream)
			if records.is_empty():
				title(v, "No races yet. Finish one to set your first score.", 24, Color("c9b98a"))
			v.add_theme_constant_override("separation", 10)
			for k in mini(records.size(), 8):
				var r: Dictionary = records[k]
				var line := HBoxContainer.new()
				v.add_child(line)
				var medal: Color = [GOLD, Color("d9dde2"), Color("d08a4a")][k] if k < 3 else cream
				var rk := title(line, "%d." % (k + 1), 30, medal)
				rk.custom_minimum_size = Vector2(56, 0)
				rk.autowrap_mode = TextServer.AUTOWRAP_OFF
				var sc := title(line, str(int(r.score)), 30, medal)
				sc.custom_minimum_size = Vector2(120, 0)
				sc.autowrap_mode = TextServer.AUTOWRAP_OFF
				sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
				var pl: int = int(r.place)
				var what := ("#%d" % pl if pl > 0 else "out") + "  vs %d  %d coins" % [int(r.bots), int(r.coins)]
				var info := title(line, what, 21, Color("c9b98a"))
				info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				info.autowrap_mode = TextServer.AUTOWRAP_OFF
				info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			title(v, "Online world ranking: coming soon", 20, cream)
			icon_button(_draw_back, menu.bind("main"), false)
		"shop":
			title(v, "POWER-UPS", 54, GOLD)
			title(v, "Your coins: %d" % wallet, 30, cream)
			var goods := [["shield", "SHIELD", "Blocks the next hit", 30], ["ankh", "RESPAWN", "One extra comeback", 50], ["heart", "EXTRA LIFE", "Start with 4 hearts", 20], ["trophy", "LUCKY DIE", "Re-roll once a game", 40], ["banana", "BANANA", "A gorilla saves you once", 80]]
			for g in goods:
				var line := HBoxContainer.new()
				line.add_theme_constant_override("separation", 14)
				v.add_child(line)
				var pic := TextureRect.new()
				pic.texture = ui_tex(g[0])
				pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				pic.custom_minimum_size = Vector2(70, 70)
				line.add_child(pic)
				var words := VBoxContainer.new()
				words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				words.add_theme_constant_override("separation", -4)
				line.add_child(words)
				title(words, g[1], 28, cream).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
				title(words, g[2], 19, Color("c9b98a")).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
				var price := menu_button(line, str(g[3]), wood, menu.bind("shop"), false, 30)
				price.custom_minimum_size = Vector2(130, 78)
				price.add_theme_stylebox_override("disabled", _card_plain(Color("3a342c")))
			title(v, "Buying opens in a later update. Coins you win are saved.", 20, cream)
			icon_button(_draw_back, menu.bind("main"), false)
		"settings":
			title(v, "SETTINGS", 54, GOLD)
			title(v, "CAMERA", 28, cream)
			menu_button(v, "FOLLOW THE TURN", green if view_mode == "turn" else wood, set_view.bind("turn"), true, 32)
			menu_button(v, "STAY ON MY PLAYER", green if view_mode == "mine" else wood, set_view.bind("mine"), true, 32)
			title(v, "A gold arrow always marks whose turn it is", 20, cream)
			title(v, "SOUND", 28, cream)
			menu_button(v, "ON" if sound_on else "OFF", green if sound_on else wood, toggle_sound, true, 36)
			icon_button(_draw_back, menu.bind("main"), false)


func _card_style(c: Color) -> StyleBox:
	# tall number card: plain gold-rimmed plaque (the wide button art would squash here)
	var s := _round(c, 20, 7, Color("ffd76a"))
	s.border_width_bottom = 14
	s.content_margin_bottom = 70  # leaves room for the row of faces under the number
	return s


func step_bots(d: int) -> void:
	bot_count = clampi(bot_count + d, 1, 5)
	menu("bots")


func _key(b: Button) -> void:
	# square stepper key: plain plaque, since the wide button art would squash
	b.custom_minimum_size = Vector2(124, 124)
	b.add_theme_stylebox_override("normal", _card_plain(Color("6b4a2c")))
	b.add_theme_stylebox_override("hover", _card_plain(Color("83603c")))
	b.add_theme_stylebox_override("pressed", _card_plain(Color("52381f")))
	b.add_theme_stylebox_override("disabled", _card_plain(Color("3a342c")))


func _card_plain(c: Color) -> StyleBoxFlat:
	var s := _round(c, 20, 6, Color("ffd76a"))
	s.border_width_bottom = 14
	return s


func _draw_faces(c: Control) -> void:
	# one little face per rival
	var w := 40.0
	var x0 := c.size.x / 2.0 - (bot_count * w + (bot_count - 1) * 8.0) / 2.0
	for k in bot_count:
		var col: Color = ROSTER[k + 1].color
		var at := Vector2(x0 + k * (w + 8.0), 4)
		c.draw_rect(Rect2(at - Vector2(3, 3), Vector2(w + 6, w + 6)), Color("2a2118"))
		c.draw_rect(Rect2(at, Vector2(w, w)), col)
		c.draw_rect(Rect2(at + Vector2(7, 15), Vector2(w - 14, w - 19)), Color("c68e5f"))
		c.draw_rect(Rect2(at + Vector2(2, 9), Vector2(w - 4, 7)), Color("b08d57"))


func begin_picked() -> void:
	begin(bot_count)


func begin(bots: int) -> void:
	bot_count = bots
	in_lobby = false
	lobby.visible = false
	results.visible = false
	for n in hud_nodes:
		n.visible = true
	lbl_hint.visible = false
	turn_bar.visible = false
	start_run()


func set_view(mode: String) -> void:
	view_mode = mode
	save_settings()
	menu("settings")


func toggle_sound() -> void:
	sound_on = not sound_on
	AudioServer.set_bus_mute(0, not sound_on)
	save_settings()
	menu("settings")


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "view", view_mode)
	cf.set_value("game", "sound", sound_on)
	cf.set_value("game", "wallet", wallet)
	cf.set_value("game", "records", records)
	cf.set_value("game", "stats", stats)
	cf.save("user://settings.cfg")


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		view_mode = cf.get_value("game", "view", "turn")
		sound_on = cf.get_value("game", "sound", true)
		wallet = cf.get_value("game", "wallet", 0)
		records = cf.get_value("game", "records", [])
		stats = cf.get_value("game", "stats", {"races": 0, "wins": 0})
	AudioServer.set_bus_mute(0, not sound_on)


func game_over(me: Dictionary) -> void:
	# Results board: headline, standings, then play again or back to the lobby.
	set_die(0)
	clear_buttons()
	refresh_ui()
	for n in [die, lbl_hint, turn_bar]:
		n.visible = false
	var place := finished.find(me) + 1
	var head := "OUT AT SLAB %d" % me.pos
	var head_c := Color("ff6b5e")
	if place == 1:
		head = "YOU WIN!"
		head_c = GOLD
	elif place > 1:
		head = "FINISHED #%d" % place
		head_c = Color("fff3c4")
	say("Game over")
	wallet += me.coins  # banked for the power-up shop
	# score: placing counts most, then what you kept; fewer rounds is better
	var score: int = [0, 1000, 600, 350, 200, 120, 80][mini(place, 6)] + me.coins * 20 + me.hearts * 50 + me.revives * 100 + bot_count * 60 - round_no * 4
	if me.out:
		score = me.pos * 3 + me.coins * 20
	score = maxi(score, 0)
	var entry := {"score": score, "place": place, "coins": me.coins, "rounds": round_no, "bots": bot_count, "date": Time.get_date_string_from_system()}
	var rank := 0
	while rank < records.size() and int(records[rank].score) >= score:
		rank += 1
	records.insert(rank, entry)
	if records.size() > 10:
		records.resize(10)
	stats.races = int(stats.races) + 1
	if place == 1:
		stats.wins = int(stats.wins) + 1
	save_settings()
	if place == 1:
		fireworks(me.a.position)
	sfx.play("win" if place == 1 else "bad")
	for c in results.get_children():
		c.queue_free()
	var box_v := VBoxContainer.new()
	box_v.add_theme_constant_override("separation", 14)
	results.add_child(box_v)
	title(box_v, head, 62, head_c)
	# standings: finishers in order, then whoever got furthest, then those knocked out
	var order: Array[Dictionary] = []
	order.append_array(finished)
	var rest: Array[Dictionary] = []
	for p in players:
		if not p.done:
			rest.append(p)
	rest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (not a.out and b.out) or (a.out == b.out and a.pos > b.pos))
	order.append_array(rest)
	for k in order.size():
		var p := order[k]
		var state := "treasure" if p.done else ("out" if p.out else "slab %d" % p.pos)
		var c: Color = p.color
		title(box_v, "%d.  %s  -  %s  -  %d coins" % [k + 1, "YOU" if not p.bot else p.name, state, p.coins], 26, c.lightened(0.45))
	title(box_v, "SCORE  %d" % score, 40, GOLD)
	if rank == 0:
		title(box_v, "NEW BEST!", 30, Color("7dff9b"))
	elif rank < 10:
		title(box_v, "Rank %d on your leaderboard" % (rank + 1), 22, Color("fff3c4"))
	menu_button(box_v, "PLAY AGAIN", Color("3fae5a"), begin.bind(bot_count))
	menu_button(box_v, "LOBBY", Color("6b4a2c"), show_lobby)
	results.visible = true


# ---------------------------------------------------------------- per frame

func _flock() -> void:
	# a few birds cross the sky now and then
	var f := Node3D.new()
	world.add_child(f)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	f.position = cam.position + Vector3(-34.0 * side, rng.randf_range(6, 12), -rng.randf_range(18, 34))
	f.rotation.y = -PI / 2.0 * side
	for k in rng.randi_range(3, 5):
		var b: Node3D = Animals.build("bird", self, [Color("f4f4f0"), Color("3fbf5a"), Color("3f9fe0"), Color("f2d24a")][rng.randi_range(0, 3)])
		var rank := ceilf(k / 2.0)
		b.position = Vector3((k % 2 * 2 - 1) * rank * 0.9, 0, rank * 0.9)
		b.scale = Vector3.ONE * 1.4
		f.add_child(b)
	var tw := f.create_tween()
	tw.tween_property(f, "position:x", f.position.x + 70.0 * side, 9.0)
	tw.tween_callback(f.queue_free)


func _input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventScreenTouch or event is InputEventMouseButton) and event.pressed
	if not pressed:
		return
	if in_cine:
		skip_intro = true
		return
	if jump_open:
		jump_hit = true
	elif await_roll:  # a tap anywhere rolls, not only on the die
		await_roll = false
		rolled.emit()


func _process(delta: float) -> void:
	if not world:
		return
	clock += delta
	# self-heal: if the window was reshaped and the UI is still laid out for the old shape, refit it
	if Engine.get_frames_drawn() % 20 == 0 and Vector2i(get_viewport().get_visible_rect().size) != ui_layer.size_2d_override:
		apply_safe_area()
	var real := delta / maxf(Engine.time_scale, 0.05)  # unscaled frame time
	zoom_k = move_toward(zoom_k, zoom_to, real * 3.0)
	slow_now = move_toward(slow_now, slow_to, real * 3.5)
	if not stopping:
		Engine.time_scale = slow_now
	for g in pickups.values():
		g.rotation.y += delta * 3.0
	for i in reveals:  # signs pop in as runners approach
		var rv: Dictionary = reveals[i]
		if rv.shown:
			continue
		for p in players:
			if active(p) and i - p.pos >= -1 and i - p.pos <= rv.radius:
				rv.shown = true
				for n in rv.nodes:
					n.visible = true
				if rv.board:
					var bd: Sprite3D = rv.board
					bd.scale = Vector3.ONE * 0.05
					bd.create_tween().tween_property(bd, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				if not in_lobby and not in_cine:
					if rv.kind == "tiger":
						sfx.play("growl", -7.0)  # something is in that bush
					else:
						sfx.play("coin", -16.0, 0.7)
				break
	# race-bar pins glide towards where their runners are
	var gliding := false
	for p in players:
		var cur: float = pin_at.get(p.name, float(p.pos))
		var nxt := lerpf(cur, float(p.pos), minf(1.0, delta * 7.0))
		if absf(nxt - float(p.pos)) < 0.01:
			nxt = float(p.pos)
		gliding = gliding or nxt != cur
		pin_at[p.name] = nxt
	var nbo := lerpf(pin_bo, float(bo), minf(1.0, delta * 5.0))
	gliding = gliding or absf(nbo - pin_bo) > 0.002
	pin_bo = nbo
	if gliding or not hud_current.is_empty():  # the active pin bobs
		track.queue_redraw()
	# Keep the path uncluttered: badges show only for the next few slabs ahead of
	# whoever is moving, and only the nearest one carries its caption.
	if not focus_p.is_empty():
		var fpos: int = focus_p.pos
		var nearest := 999
		for i in reveals:
			if reveals[i].shown and i > fpos and i < nearest:
				nearest = i
		for i in reveals:
			var rv: Dictionary = reveals[i]
			if not rv.shown:
				continue
			var ahead: bool = i > fpos and i <= fpos + 3
			if rv.board:
				rv.board.visible = ahead
			rv.cap.visible = ahead and i == nearest
	update_sky(delta)
	for r in rescues:  # the vine a rescuing monkey hangs from
		if is_instance_valid(r.mk):
			var vn: Strand = r.vine
			vn.step(minf(delta, 1.0 / 30.0), r.pivot, Vector3(0, -9, 0), Vector3.UP, r.mk.position + Vector3(0, 2.16, 0))
	for c in circlers:
		c.rotation.y += delta * float(c.get_meta("w"))
	if reward_root.visible:
		reward_rays.rotation += delta * 1.3
	for i in snakes:  # cobras sleep coiled, and rear up hissing when a runner comes near
		var sn: Dictionary = snakes[i]
		var near := false
		for p in players:
			if active(p) and absi(p.pos - i) <= 2:
				near = true
		if near and not sn.was and not in_lobby and not in_cine:
			sfx.play("snake", -9.0)
		sn.was = near
		sn.node.wake_to = 1.0 if near else 0.0
	bird_in -= delta
	if bird_in <= 0.0:
		bird_in = rng.randf_range(2.5, 5.5)
		_flock()
	var gust := wind(clock)
	var dt := minf(delta, 1.0 / 30.0)
	for r in ropes.values():
		var rs: Strand = r.s
		rs.step(dt, r.a, Vector3(0, -9, 0) + gust * 0.4, Vector3.UP, r.b)
	wind_fx.position = cam.position
	var dv := boulder.position - ball_last
	ball_last = boulder.position
	var flat := Vector3(dv.x, 0, dv.z)
	if flat.length() > 0.0001:
		ball.rotate(Vector3.UP.cross(flat.normalized()).normalized(), flat.length() / 1.25)

	marker.visible = not in_lobby and not in_cine and not focus_p.is_empty()
	if in_cine:
		if is_instance_valid(cine_target):  # keep the runner making their entrance in the middle of the frame
			cine_look = cine_look.lerp(cine_target.position + Vector3(0, 1.1, 0), minf(1.0, delta * 7.0))
		if cine_smooth > 0.0:  # glide: position and aim both ease, so nothing snaps
			cam.position = cam.position.lerp(cine_pos, minf(1.0, delta * cine_smooth))
			cine_look_now = cine_look_now.lerp(cine_look, minf(1.0, delta * cine_smooth))
		else:
			cam.position = cine_pos
			cine_look_now = cine_look
		cam.look_at(cine_look_now)
		cam.fov = 62.0
		cam.h_offset = rng.randf_range(-1, 1) * shake_amt
		cam.v_offset = rng.randf_range(-1, 1) * shake_amt
		shake_amt = lerpf(shake_amt, 0.0, minf(1.0, delta * 7.0))
		return
	if in_lobby:  # slow fly-through of the map behind the menu
		lobby_t = fmod(lobby_t + delta * 0.7, float(END - 1))
		var li := int(lobby_t)
		var lp := path[li].lerp(path[li + 1], lobby_t - li)
		var side := dirs[li].cross(Vector3.UP)
		cam.position = cam.position.lerp(lp - dirs[li] * 11.0 + side * 5.0 + Vector3(0, 8.0, 0), minf(1.0, delta * 1.5))
		cam_base = cam_base.lerp(lp + dirs[li] * 9.0 + Vector3(0, 1.5, 0), minf(1.0, delta * 1.5))
		cam.look_at(cam_base)
		return
	if focus_p.is_empty():
		return
	var fa: Node3D = focus_p.a
	marker.position = fa.position + Vector3(0, 2.75 + sin(clock * 5.0) * 0.15, 0)
	marker.rotation.y += delta * 2.5
	# who the camera stands behind, and which way it faces
	var me := players[0]
	var who := focus_p
	var i: int = clampi(focus_p.pos, 0, END)
	var want := dirs[i]
	if view_mode == "mine" and active(me):
		who = me
		i = clampi(me.pos, 0, END)
		want = dirs[i]
		var to_mover: Vector3 = fa.position - me.a.position
		to_mover.y = 0.0
		if to_mover.length() > 2.5:  # turn to face whoever is moving
			want = to_mover.normalized()
	if zoom_k > 0.01 and not zoom_p.is_empty() and is_instance_valid(zoom_p.a):
		who = zoom_p  # a special move always takes the camera, whatever the view setting
		i = clampi(zoom_p.pos, 0, END)
		want = dirs[i]
	var fp: Vector3 = who.a.position
	cam_base = cam_base.lerp(Vector3(fp.x, path[i].y, fp.z), minf(1.0, real * 5.0))
	cam_yaw = lerp_angle(cam_yaw, atan2(want.x, want.z), minf(1.0, real * 2.5))
	cam_dir = Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	var z := smoothstep(0.0, 1.0, zoom_k)
	var side := cam_dir.cross(Vector3.UP)
	cam.position = cam_base - cam_dir * lerpf(7.4, 4.4, z) + side * 1.9 * z + Vector3(0, lerpf(6.6, 2.5, z), 0)
	cam.look_at((cam_base + cam_dir * 5.5 + Vector3(0, 0.6, 0)).lerp(cam_base + Vector3(0, 1.15, 0), z))
	cam.fov = lerpf(62.0, 50.0, z)
	cam.h_offset = rng.randf_range(-1, 1) * shake_amt
	cam.v_offset = rng.randf_range(-1, 1) * shake_amt
	shake_amt = lerpf(shake_amt, 0.0, minf(1.0, delta * 7.0))
