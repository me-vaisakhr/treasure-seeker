extends RefCounted
## Voxel jungle animals and props. All face -Z, like the players.
## Elephant, tiger and cobra are built on the motion rig in animal.gd.

const Rig := preload("res://animal.gd")


static func _pivot(parent: Node3D, at: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = at
	parent.add_child(p)
	return p


static func build(kind: String, m, tint := Color.WHITE) -> Node3D:
	match kind:
		"elephant":
			return _elephant(m)
		"tiger":
			return _tiger(m)
		"cobra":
			return _cobra(m)
		"monkey":
			return _monkey(m, false)
		"gorilla":
			return _monkey(m, true)
	var n := Node3D.new()
	match kind:
		"chest":
			var wood := Color("7a4f2a")
			var gold := Color("e8b530")
			m.box(n, Vector3(0.9, 0.5, 0.6), Vector3(0, 0.25, 0), wood)
			m.box(n, Vector3(0.94, 0.1, 0.64), Vector3(0, 0.28, 0), gold)
			m.box(n, Vector3(0.14, 0.2, 0.06), Vector3(0, 0.34, -0.32), gold).material_override = m.mat(gold, true)
			var lid := Node3D.new()  # hinged at the back edge
			lid.position = Vector3(0, 0.5, 0.3)
			n.add_child(lid)
			m.box(lid, Vector3(0.9, 0.22, 0.6), Vector3(0, 0.11, -0.3), wood.lightened(0.08))
			m.box(lid, Vector3(0.94, 0.08, 0.64), Vector3(0, 0.2, -0.3), gold)
			n.set_meta("lid", lid)
		"parrot", "bird":
			var body := Color("3fbf5a") if kind == "parrot" else tint
			m.box(n, Vector3(0.24, 0.26, 0.42), Vector3.ZERO, body)
			m.box(n, Vector3(0.22, 0.22, 0.22), Vector3(0, 0.16, -0.24), body.lightened(0.1))
			m.box(n, Vector3(0.1, 0.1, 0.14), Vector3(0, 0.12, -0.4), Color("e2463a") if kind == "parrot" else Color("f0a020"))
			m.box(n, Vector3(0.14, 0.06, 0.34), Vector3(0, -0.02, 0.36), Color("3f7fe0") if kind == "parrot" else body.darkened(0.2))
			for side in [-1, 1]:
				var wing := Node3D.new()
				wing.position = Vector3(side * 0.12, 0.08, 0)
				n.add_child(wing)
				m.box(wing, Vector3(0.5, 0.05, 0.3), Vector3(side * 0.25, 0, 0), body.darkened(0.15))
				var tw := wing.create_tween().set_loops()
				tw.tween_property(wing, "rotation:z", side * 0.9, 0.12)
				tw.tween_property(wing, "rotation:z", -side * 0.6, 0.12)
	return n


static func _elephant(m) -> Node3D:
	# Barrel body with a domed back, column legs with knees and toenails, a domed
	# head with fan ears, curved tusks and a six-piece tapering trunk.
	var n: Node3D = Rig.new()
	n.kind = "elephant"
	var grey := Color("8d8f96")
	var dark := grey.darkened(0.14)
	var gold := Color("e8b530")
	var chest := _pivot(n, Vector3(0, 1.55, 0))
	n.chest = chest
	m.box(chest, Vector3(1.5, 1.25, 2.1), Vector3.ZERO, grey)
	m.box(chest, Vector3(1.2, 0.26, 1.5), Vector3(0, 0.72, 0), grey)          # domed back
	m.box(chest, Vector3(1.3, 0.24, 1.7), Vector3(0, -0.7, 0), dark)          # belly
	m.box(chest, Vector3(1.3, 1.0, 0.3), Vector3(0, -0.05, 1.15), grey)       # rounded rump
	m.box(chest, Vector3(1.2, 0.9, 0.3), Vector3(0, 0.1, -1.15), grey)        # shoulders
	m.box(chest, Vector3(1.56, 0.1, 1.3), Vector3(0, 0.9, 0), Color("c0392b"))  # saddle cloth
	m.box(chest, Vector3(1.6, 0.5, 0.1), Vector3(0, 0.62, 0.66), gold)
	m.box(chest, Vector3(1.6, 0.5, 0.1), Vector3(0, 0.62, -0.66), gold)
	for z in [-0.72, 0.72]:
		for x in [-0.48, 0.48]:
			var hip := _pivot(n, Vector3(x, 1.02, z))
			m.box(hip, Vector3(0.46, 0.56, 0.46), Vector3(0, -0.26, 0), dark)
			var knee := _pivot(hip, Vector3(0, -0.52, 0))
			m.box(knee, Vector3(0.42, 0.42, 0.42), Vector3(0, -0.2, 0), dark)
			m.box(knee, Vector3(0.48, 0.12, 0.48), Vector3(0, -0.44, 0), grey.darkened(0.25))
			for tn in [-0.14, 0.0, 0.14]:
				m.box(knee, Vector3(0.1, 0.08, 0.06), Vector3(tn, -0.44, -0.26), Color("e8e2d2"))
			n.legs.append(hip)
			n.shins.append(knee)
	var head := _pivot(chest, Vector3(0, 0.42, -1.2))
	n.head = head
	m.box(head, Vector3(0.95, 0.95, 0.8), Vector3(0, 0, -0.28), grey)
	for x in [-0.23, 0.23]:
		m.box(head, Vector3(0.4, 0.24, 0.4), Vector3(x, 0.52, -0.25), grey)   # twin forehead domes
		m.box(head, Vector3(0.1, 0.1, 0.06), Vector3(x * 1.3, 0.12, -0.7), Color("1a1410"))
		m.box(head, Vector3(0.13, 0.13, 0.46), Vector3(x * 1.35, -0.38, -0.78), Color("f4efe0"))  # tusk
		var tip: MeshInstance3D = m.box(head, Vector3(0.1, 0.1, 0.3), Vector3(x * 1.35, -0.3, -1.1), Color("f4efe0"))
		tip.rotation.x = 0.45
	m.box(head, Vector3(0.5, 0.75, 0.08), Vector3(0, 0.12, -0.7), gold).material_override = m.mat(gold, true)  # forehead plate
	for side in [-1, 1]:
		var ear := _pivot(head, Vector3(side * 0.48, 0.15, -0.05))
		m.box(ear, Vector3(0.1, 1.0, 0.85), Vector3(side * 0.06, -0.1, 0.36), dark)
		m.box(ear, Vector3(0.06, 0.7, 0.55), Vector3(side * 0.12, -0.12, 0.36), Color("b89aa0"))
		n.ears.append(ear)
	var seg := _pivot(head, Vector3(0, -0.3, -0.72))
	for k in 6:  # trunk: each piece hangs from the one above
		var w := 0.34 - k * 0.034
		m.box(seg, Vector3(w, 0.3, w), Vector3(0, -0.14, 0), grey if k % 2 == 0 else dark)
		n.chain.append(seg)
		if k < 5:
			seg = _pivot(seg, Vector3(0, -0.28, 0))
	var tl := _pivot(chest, Vector3(0, 0.3, 1.3))
	for k in 3:
		m.box(tl, Vector3(0.1, 0.3, 0.1), Vector3(0, -0.15, 0), dark)
		n.tail.append(tl)
		if k < 2:
			tl = _pivot(tl, Vector3(0, -0.3, 0))
	m.box(tl, Vector3(0.16, 0.16, 0.16), Vector3(0, -0.34, 0), Color("2a2118"))
	return n


static func _tiger(m) -> Node3D:
	# A heavy cat: deep chest and lighter hips (two parts, so the spine flexes),
	# a thick neck, a big broad head with cheek ruff and hinged jaw, sturdy
	# jointed legs on large white paws, and a thick six-piece ringed tail.
	# Everything hangs off "core", which pitches the whole animal in a leap.
	var n: Node3D = Rig.new()
	n.kind = "tiger"
	var orange := Color("f08a24")
	var deep := Color("d9701a")
	var white := Color("f6f1e4")
	var black := Color("1c1410")
	var core := _pivot(n, Vector3.ZERO)
	core.scale = Vector3.ONE * 1.22
	n.core = core
	var chest := _pivot(core, Vector3(0, 0.85, -0.35))
	var rump := _pivot(core, Vector3(0, 0.85, 0.1))
	n.chest = chest
	n.rump = rump
	m.box(chest, Vector3(0.72, 0.68, 0.95), Vector3.ZERO, orange)
	m.box(chest, Vector3(0.56, 0.14, 0.62), Vector3(0, 0.38, 0.05), deep)       # shoulder blades
	m.box(chest, Vector3(0.5, 0.16, 0.85), Vector3(0, -0.36, 0), white)        # chest and belly
	m.box(chest, Vector3(0.5, 0.5, 0.34), Vector3(0, 0.12, -0.56), orange)     # thick neck
	m.box(chest, Vector3(0.36, 0.2, 0.3), Vector3(0, -0.12, -0.58), white)     # throat
	m.box(rump, Vector3(0.6, 0.56, 0.9), Vector3(0, -0.02, 0.42), orange)
	m.box(rump, Vector3(0.46, 0.14, 0.8), Vector3(0, -0.32, 0.42), white)
	m.box(rump, Vector3(0.56, 0.5, 0.32), Vector3(0, -0.02, -0.08), deep)      # waist
	for k in 3:
		m.box(chest, Vector3(0.75, 0.46, 0.09), Vector3(0, 0.13, -0.3 + k * 0.28), black)
		m.box(rump, Vector3(0.63, 0.4, 0.09), Vector3(0, 0.1, 0.16 + k * 0.28), black)
	for i in 4:
		var front := i < 2
		var x := -0.25 if i % 2 == 0 else 0.25
		var hip := _pivot(chest if front else rump, Vector3(x, -0.26, -0.28) if front else Vector3(x, -0.22, 0.66))
		var thick := 0.25 if front else 0.3
		m.box(hip, Vector3(thick, 0.34, thick + 0.08), Vector3(0, -0.15, 0), orange)
		m.box(hip, Vector3(thick + 0.02, 0.07, thick + 0.1), Vector3(0, -0.08, 0), black)
		m.box(hip, Vector3(thick + 0.02, 0.07, thick + 0.1), Vector3(0, -0.24, 0), black)
		var knee := _pivot(hip, Vector3(0, -0.3, 0))
		m.box(knee, Vector3(0.2, 0.26, 0.22), Vector3(0, -0.12, 0), deep)
		m.box(knee, Vector3(0.22, 0.06, 0.24), Vector3(0, -0.1, 0), black)
		m.box(knee, Vector3(0.28, 0.12, 0.36), Vector3(0, -0.27, -0.06), white)  # big paw
		n.legs.append(hip)
		n.shins.append(knee)
	var head := _pivot(chest, Vector3(0, 0.22, -0.68))
	n.head = head
	m.box(head, Vector3(0.64, 0.56, 0.5), Vector3(0, 0.05, -0.22), orange)
	m.box(head, Vector3(0.84, 0.3, 0.28), Vector3(0, -0.1, -0.18), white)        # cheek ruff
	m.box(head, Vector3(0.38, 0.22, 0.2), Vector3(0, -0.04, -0.52), white)       # short broad muzzle
	m.box(head, Vector3(0.14, 0.09, 0.06), Vector3(0, 0.04, -0.63), Color("e58a9a"))
	m.box(head, Vector3(0.1, 0.34, 0.06), Vector3(0, 0.25, -0.47), black)
	m.box(head, Vector3(0.3, 0.07, 0.3), Vector3(0, 0.34, -0.2), black)          # crown stripe
	for x in [-0.23, 0.23]:
		m.box(head, Vector3(0.19, 0.19, 0.1), Vector3(x, 0.4, -0.1), black)      # ear
		m.box(head, Vector3(0.09, 0.09, 0.04), Vector3(x, 0.41, -0.05), white)
		m.box(head, Vector3(0.12, 0.1, 0.05), Vector3(x * 0.74, 0.13, -0.48), Color("f7e04a")).material_override = m.mat(Color("f7e04a"), true)
		m.box(head, Vector3(0.04, 0.1, 0.03), Vector3(x * 0.74, 0.13, -0.51), black)
		m.box(head, Vector3(0.06, 0.15, 0.06), Vector3(x * 0.52, -0.2, -0.58), white)  # upper fang
		m.box(head, Vector3(0.05, 0.18, 0.3), Vector3(x * 1.36, 0.2, -0.22), black)    # face stripe
		m.box(head, Vector3(0.05, 0.12, 0.2), Vector3(x * 1.36, 0.0, -0.3), black)
	var jaw := _pivot(head, Vector3(0, -0.17, -0.36))
	n.jaw = jaw
	m.box(jaw, Vector3(0.34, 0.09, 0.3), Vector3(0, -0.04, -0.13), white)
	m.box(jaw, Vector3(0.28, 0.03, 0.26), Vector3(0, 0.01, -0.13), Color("9a2a2a"))
	for x in [-0.1, 0.1]:
		m.box(jaw, Vector3(0.05, 0.1, 0.05), Vector3(x, 0.04, -0.25), white)
	var seg := _pivot(rump, Vector3(0, 0.15, 0.86))
	for k in 6:
		m.box(seg, Vector3(0.15 - k * 0.006, 0.15 - k * 0.006, 0.27), Vector3(0, 0, 0.12), orange if k % 2 == 0 else black)
		n.chain.append(seg)
		if k < 5:
			seg = _pivot(seg, Vector3(0, 0, 0.25))
	return n


static func _monkey(m, gorilla: bool) -> Node3D:
	# A small langur-like monkey: round head with a pale face and ears, long
	# jointed arms (longer than its legs), pale hands and feet, a six-piece tail.
	# The gorilla is the same skeleton made huge and heavy: black coat, silver
	# back, massive shoulders and arms, a crest and brow ridge, and no tail.
	var n: Node3D = Rig.new()
	n.kind = "monkey"
	n.heavy = gorilla
	var brown := Color("45414b") if gorilla else Color("8a5a32")
	var dark := brown.darkened(0.18)
	var tan := Color("77717c") if gorilla else Color("e2bd92")  # face, hands, feet
	var chest := _pivot(n, Vector3(0, 0.62, 0))
	n.chest = chest
	m.box(chest, Vector3(0.42, 0.5, 0.32), Vector3.ZERO, brown)
	m.box(chest, Vector3(0.28, 0.34, 0.05), Vector3(0, -0.02, -0.17), tan)  # pale belly
	var head := _pivot(chest, Vector3(0, 0.36, 0))
	n.head = head
	m.box(head, Vector3(0.4, 0.36, 0.36), Vector3(0, 0.12, 0), brown)
	m.box(head, Vector3(0.28, 0.26, 0.06), Vector3(0, 0.1, -0.19), tan)
	m.box(head, Vector3(0.16, 0.1, 0.08), Vector3(0, 0.03, -0.23), tan.darkened(0.12))  # muzzle
	m.box(head, Vector3(0.08, 0.03, 0.02), Vector3(0, -0.01, -0.275), Color("1a1410"))  # mouth
	for x in [-0.24, 0.24]:
		m.box(head, Vector3(0.1, 0.2, 0.08) if not gorilla else Vector3(0.07, 0.12, 0.06), Vector3(x, 0.14, 0.0), tan)  # ear
		m.box(head, Vector3(0.09, 0.09, 0.03), Vector3(x * 0.32, 0.16, -0.225), Color("fff8e1"))  # eye white
		m.box(head, Vector3(0.05, 0.06, 0.03), Vector3(x * 0.3, 0.155, -0.24), Color("1a1410"))
		m.box(head, Vector3(0.025, 0.03, 0.02), Vector3(x * 0.12, 0.05, -0.275), Color("1a1410"))  # nostril
	for side in [-1, 1]:
		var sh := _pivot(chest, Vector3(side * 0.26, 0.18, 0))
		m.box(sh, Vector3(0.12, 0.32, 0.12), Vector3(0, -0.15, 0), dark)
		var el := _pivot(sh, Vector3(0, -0.3, 0))
		m.box(el, Vector3(0.11, 0.3, 0.11), Vector3(0, -0.14, 0), brown)
		m.box(el, Vector3(0.14, 0.1, 0.14), Vector3(0, -0.33, 0), tan)          # hand
		n.arms.append(sh)
		n.elbows.append(el)
		var hip := _pivot(chest, Vector3(side * 0.14, -0.26, 0))
		m.box(hip, Vector3(0.14, 0.24, 0.14), Vector3(0, -0.11, 0), dark)
		var knee := _pivot(hip, Vector3(0, -0.22, 0))
		m.box(knee, Vector3(0.12, 0.22, 0.12), Vector3(0, -0.1, 0), brown)
		m.box(knee, Vector3(0.14, 0.08, 0.2), Vector3(0, -0.24, -0.03), tan)    # foot
		n.legs.append(hip)
		n.shins.append(knee)
		if gorilla:  # slabs of muscle on the upper arms and shoulders
			m.box(sh, Vector3(0.22, 0.34, 0.22), Vector3(0, -0.14, 0), brown)
			m.box(el, Vector3(0.18, 0.3, 0.18), Vector3(0, -0.14, 0), dark)
			m.box(chest, Vector3(0.24, 0.2, 0.3), Vector3(side * 0.3, 0.24, 0), brown)
	if gorilla:
		m.box(chest, Vector3(0.6, 0.4, 0.4), Vector3(0, 0.1, 0), brown)                 # barrel chest
		m.box(chest, Vector3(0.5, 0.36, 0.06), Vector3(0, 0.02, 0.2), Color("b9b6b2"))  # silver back
		m.box(chest, Vector3(0.4, 0.26, 0.05), Vector3(0, 0.12, -0.2), Color("625c68")) # bare chest
		m.box(head, Vector3(0.24, 0.14, 0.3), Vector3(0, 0.36, 0.02), brown)            # crest
		m.box(head, Vector3(0.4, 0.07, 0.1), Vector3(0, 0.235, -0.2), dark)             # heavy brow ridge
		n.scale = Vector3.ONE * 1.8
		return n
	var seg := _pivot(chest, Vector3(0, -0.2, 0.17))
	for k in 6:
		m.box(seg, Vector3(0.08, 0.08, 0.2), Vector3(0, 0, 0.09), brown if k % 2 == 0 else dark)
		n.chain.append(seg)
		if k < 5:
			seg = _pivot(seg, Vector3(0, 0, 0.18))
	return n


static func _cobra(m) -> Node3D:
	# Two loops of banded coil tapering to a tail, and a five-piece neck that
	# can lie flat, rear into an S or lunge. Hood, pale belly bars, spectacle
	# mark, red eyes, fangs and a forked tongue. Its front faces +Z, towards
	# runners arriving on the slab.
	var n: Node3D = Rig.new()
	n.kind = "cobra"
	n.wake_to = 0.0
	var lime := Color("9bcf3a")
	var gold := Color("e8d23a")
	var dark := Color("3a4a1c")
	var pale := Color("f1ecc4")
	for k in 15:
		var ang := k * TAU / 8.0
		var rad := 0.62 - k * 0.022
		var s := 0.32 - k * 0.011
		var c := lime if k % 3 == 0 else (gold if k % 3 == 1 else dark)
		var piece: MeshInstance3D = m.box(n, Vector3.ONE * s, Vector3(cos(ang) * rad, 0.41 + (0.16 if k > 7 else 0.0) + k * 0.004, sin(ang) * rad - 0.15), c)
		piece.rotation.y = -ang
		piece.set_meta("y", piece.position.y)
		n.coil.append(piece)
	m.box(n, Vector3(0.1, 0.1, 0.34), Vector3(0.68, 0.34, 0.2), dark)  # tail tip
	var root := _pivot(n, Vector3(0, 0.62, -0.12))
	n.neck_root = root
	n.neck_z = root.position.z
	var seg := root
	for k in 5:
		m.box(seg, Vector3(0.27 - k * 0.01, 0.26, 0.27 - k * 0.01), Vector3(0, 0.12, 0), lime if k % 2 == 0 else gold)
		m.box(seg, Vector3(0.2, 0.2, 0.04), Vector3(0, 0.12, 0.14), pale)  # belly bar
		n.chain.append(seg)
		if k == 3:
			var hood := _pivot(seg, Vector3(0, 0.16, -0.09))
			n.hood = hood
			m.box(hood, Vector3(0.86, 0.6, 0.07), Vector3.ZERO, lime.darkened(0.2))
			m.box(hood, Vector3(0.6, 0.42, 0.05), Vector3(0, 0.0, 0.05), gold)
			for ex in [-0.14, 0.14]:
				m.box(hood, Vector3(0.14, 0.14, 0.03), Vector3(ex, 0.06, -0.05), pale)  # spectacle mark
		if k < 4:
			seg = _pivot(seg, Vector3(0, 0.24, 0))
	var head := _pivot(seg, Vector3(0, 0.24, 0))
	n.head = head
	m.box(head, Vector3(0.42, 0.24, 0.52), Vector3(0, 0.1, 0.12), lime)
	m.box(head, Vector3(0.38, 0.06, 0.46), Vector3(0, -0.03, 0.14), Color("7a1f1f"))  # open mouth
	m.box(head, Vector3(0.36, 0.06, 0.44), Vector3(0, -0.09, 0.12), pale)
	for ex in [-0.13, 0.13]:
		m.box(head, Vector3(0.09, 0.09, 0.05), Vector3(ex, 0.14, 0.37), Color("ff3b2e")).material_override = m.mat(Color("ff3b2e"), true)
		m.box(head, Vector3(0.04, 0.13, 0.04), Vector3(ex * 0.7, -0.05, 0.36), Color("ffffff"))  # fang
	var tongue: MeshInstance3D = m.box(head, Vector3(0.06, 0.03, 0.36), Vector3(0, -0.04, 0.52), Color("ff3b2e"))
	n.tongue = tongue
	return n
