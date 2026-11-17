extends Node
## All sound is synthesised at startup (no audio files): retro blips to match the pixel look.

const RATE := 22050

var streams := {}
var players: Array[AudioStreamPlayer] = []
var next := 0
var rng := RandomNumberGenerator.new()
var chirp_in := 3.0
var rain_player: AudioStreamPlayer
var day_player: AudioStreamPlayer
var night_player: AudioStreamPlayer
var music_player: AudioStreamPlayer


func _ready() -> void:
	rng.randomize()
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)

	streams["step"] = wav(mix(noise(0.06, 0.25, 6.0), tone(0.07, 120, 70, "sine", 5.0)))
	streams["jump"] = wav(tone(0.2, 280, 720, "sine", 2.0))
	streams["land"] = wav(mix(noise(0.1, 0.15, 6.0), tone(0.12, 90, 50, "sine", 4.0)))
	var dice := PackedFloat32Array()
	for k in 5:
		dice.append_array(noise(0.03, 0.8, 8.0))
		dice.append_array(silence(0.025))
	streams["dice"] = wav(dice)
	streams["good"] = wav(gain(cat([tone(0.09, 660, 660, "square", 3.0), tone(0.22, 990, 990, "square", 4.0)]), 0.45))
	streams["bad"] = wav(gain(tone(0.38, 320, 110, "saw", 2.5), 0.5))
	streams["crumble"] = wav(mix(gain(noise(1.0, 0.06, 2.5), 1.6), gain(noise(1.0, 0.7, 5.0), 0.3)))
	streams["boulder"] = wav(mix(gain(noise(1.0, 0.035, 1.2), 1.8), tone(1.0, 52, 40, "sine", 1.0)))
	streams["rope"] = wav(gain(noise(0.8, 0.3, 1.2, true), 0.8))
	streams["bump"] = wav(mix(gain(tone(0.1, 210, 90, "square", 6.0), 0.5), noise(0.05, 0.5, 8.0)))
	streams["win"] = wav(gain(cat([tone(0.11, 523, 523, "square", 2.0), tone(0.11, 659, 659, "square", 2.0), tone(0.11, 784, 784, "square", 2.0), tone(0.45, 1047, 1047, "square", 3.0)]), 0.45))
	streams["crush"] = wav(mix(gain(noise(0.6, 0.1, 4.0), 1.6), tone(0.6, 70, 30, "sine", 3.0)))
	streams["reborn"] = wav(gain(cat([tone(0.08, 392, 392, "sine", 1.0), tone(0.08, 523, 523, "sine", 1.0), tone(0.08, 659, 659, "sine", 1.0), tone(0.08, 784, 784, "sine", 1.0), tone(0.4, 1047, 1047, "sine", 3.0)]), 0.7))
	streams["mystery"] = wav(gain(cat([tone(0.12, 500, 700, "sine", 1.0), tone(0.12, 700, 500, "sine", 1.0), tone(0.25, 500, 950, "sine", 2.0)]), 0.7))
	streams["snake"] = wav(gain(noise(0.7, 0.9, 2.0, true, true), 0.9))
	streams["fire"] = wav(gain(noise(0.35, 0.22, 3.0, true), 0.9))
	streams["coin"] = wav(gain(cat([tone(0.05, 1320, 1320, "square", 2.0), tone(0.14, 1760, 1760, "square", 4.0)]), 0.35))
	streams["roar"] = wav(mix(gain(noise(0.9, 0.08, 1.5, true), 1.8), gain(tone(0.9, 95, 60, "saw", 1.0), 0.6)))
	streams["trumpet"] = wav(gain(cat([tone(0.25, 300, 520, "saw", 0.5), tone(0.45, 520, 360, "saw", 1.5)]), 0.5))
	streams["monkey"] = wav(gain(cat([tone(0.06, 900, 1300, "square", 1.0), silence(0.04), tone(0.06, 1000, 1400, "square", 1.0), silence(0.04), tone(0.06, 900, 1300, "square", 1.0), silence(0.04), tone(0.1, 1200, 800, "square", 2.0)]), 0.35))
	streams["splash"] = wav(gain(noise(0.4, 0.5, 4.0), 0.6))
	streams["chirp"] = wav(gain(cat([tone(0.06, 2600, 3500, "sine", 1.5), silence(0.05), tone(0.06, 2900, 3700, "sine", 1.5), silence(0.04), tone(0.09, 3300, 2500, "sine", 2.0)]), 0.25))

	streams["thunder"] = wav(mix(gain(noise(2.4, 0.03, 1.4), 2.2), tone(2.4, 46, 30, "sine", 1.2)))
	streams["punch"] = streams["bump"]
	streams["growl"] = streams["roar"]
	streams["gorilla"] = streams["monkey"]
	for id in ["punch2", "punch3", "kick", "ko"]:  # stand-ins until the recordings are found
		streams[id] = streams["punch"]
	streams["gong"] = streams["good"]
	streams["whoosh"] = streams["jump"]
	streams["oof"] = streams["bad"]
	streams["bodyfall"] = streams["land"]
	# recordings in res://sfx/ (see tools/import_sounds.py) replace the synthesised versions
	for id in ["roar", "growl", "snake", "trumpet", "monkey", "gorilla", "thunder", "punch", "crumble", "boulder", "dice", "step", "coin", "gong", "whoosh", "punch2", "punch3", "kick", "oof", "ko", "bodyfall"]:
		var path := "res://sfx/%s.wav" % id
		if ResourceLoader.exists(path):
			streams[id] = load(path)
	rain_player = AudioStreamPlayer.new()
	rain_player.stream = looped("res://sfx/rain.wav", wav(gain(noise(3.0, 0.6, 0.0, false, true), 0.5), true))
	rain_player.volume_db = -60.0
	add_child(rain_player)
	rain_player.play()

	# looping bed: wind in the valley plus distant waterfall hiss
	day_player = AudioStreamPlayer.new()
	day_player.stream = looped("res://sfx/amb_day.wav", wav(ambience(6.0), true))
	day_player.volume_db = -11.0
	add_child(day_player)
	day_player.play()
	night_player = AudioStreamPlayer.new()
	night_player.stream = looped("res://sfx/amb_night.wav", wav(ambience(6.0), true))
	night_player.volume_db = -60.0
	add_child(night_player)
	night_player.play()


func start_music() -> void:
	# background music, if sfx/music.ogg is there: loops quietly under everything
	if music_player or not ResourceLoader.exists("res://sfx/music.ogg"):
		return
	var s: AudioStreamOggVorbis = load("res://sfx/music.ogg").duplicate()
	s.loop = true
	music_player = AudioStreamPlayer.new()
	music_player.stream = s
	music_player.volume_db = -15.0
	add_child(music_player)
	music_player.play()


func duck(on: bool) -> void:
	# music steps back during close-up moments so roars and hits come through
	if music_player:
		create_tween().tween_property(music_player, "volume_db", -24.0 if on else -15.0, 0.4)


func looped(path: String, fallback: AudioStream) -> AudioStream:
	if not ResourceLoader.exists(path):
		return fallback
	var s: AudioStreamWAV = load(path).duplicate()
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = int(s.get_length() * s.mix_rate)
	return s


func hit() -> void:
	# one of three punch recordings, so a flurry does not sound like a machine gun
	play(["punch", "punch2", "punch3"][rng.randi_range(0, 2)], -1.0)


func set_night(k: float) -> void:
	day_player.volume_db = lerpf(-11.0, -45.0, k)
	night_player.volume_db = lerpf(-45.0, -9.0, k)


func _process(delta: float) -> void:
	chirp_in -= delta
	if chirp_in <= 0.0:
		chirp_in = rng.randf_range(2.5, 7.0)
		play("chirp", -6.0, rng.randf_range(0.8, 1.3))


func set_rain(k: float) -> void:
	rain_player.volume_db = lerpf(-60.0, -13.0, k)


func play(id: String, vol := 0.0, pitch := 1.0) -> void:
	var p := players[next]
	next = (next + 1) % players.size()
	p.stream = streams[id]
	p.volume_db = vol
	p.pitch_scale = pitch * rng.randf_range(0.94, 1.06)
	p.play()


# ---------------------------------------------------------------- synthesis

func silence(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	return out


func tone(dur: float, f0: float, f1: float, shape: String, decay: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += lerpf(f0, f1, t) / RATE
		var x := fmod(ph, 1.0)
		var v := sin(x * TAU)
		if shape == "square":
			v = 1.0 if x < 0.5 else -1.0
		elif shape == "saw":
			v = x * 2.0 - 1.0
		out[i] = v * exp(-decay * t) * minf(1.0, i / 80.0) * minf(1.0, (n - i) / 80.0)
	return out


## lp: 0..1 low-pass amount (small = dark rumble). bell: swell in and out. hp: hiss only.
func noise(dur: float, lp: float, decay: float, bell := false, hp := false) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / n
		var w := rng.randf_range(-1.0, 1.0)
		y += (w - y) * lp
		var v := (w - y) if hp else y / maxf(lp, 0.15)
		var env := sin(t * PI) if bell else exp(-decay * t)
		out[i] = v * env * minf(1.0, i / 60.0) * minf(1.0, (n - i) / 60.0)
	return out


func mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate() if a.size() >= b.size() else b.duplicate()
	var other := b if a.size() >= b.size() else a
	for i in other.size():
		out[i] += other[i]
	return out


func cat(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in parts:
		out.append_array(p)
	return out


func gain(a: PackedFloat32Array, g: float) -> PackedFloat32Array:
	for i in a.size():
		a[i] *= g
	return a


func ambience(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var mid := 0.0
	for i in n:
		var t := float(i) / n
		var w := rng.randf_range(-1.0, 1.0)
		low += (w - low) * 0.012
		mid += (w - mid) * 0.35
		var gust := 0.6 + 0.4 * sin(t * TAU * 2.0)
		out[i] = low * 9.0 * gust + mid * 0.07
	# blend the tail into the head so the loop has no click
	var fade := int(0.4 * RATE)
	for i in fade:
		var a := float(i) / fade
		out[n - fade + i] = out[n - fade + i] * (1.0 - a) + out[i] * a
	return out


func wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i] * 0.6, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = int(0.4 * RATE)
		s.loop_end = samples.size()
	return s
