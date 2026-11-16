extends RefCounted
## Verlet chain drawn as flat boxes. Used for scarves, skirt strips and ropes.

var pts := PackedVector3Array()
var prev := PackedVector3Array()
var seg := 0.2
var meshes: Array[MeshInstance3D] = []


func _init(parent: Node, n: int, seg_len: float, size: Vector2, material: Material, start: Vector3, dir := Vector3.DOWN) -> void:
	seg = seg_len
	for i in n + 1:
		pts.append(start + dir * seg * i)
	prev = pts.duplicate()
	for i in n:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(size.x, size.y, seg_len * 1.08)
		mi.mesh = bm
		mi.material_override = material
		mi.top_level = true
		parent.add_child(mi)
		meshes.append(mi)


## head is pinned. tail (optional) pins the other end, making a slack rope.
## axis/radius (optional) keep points outside a vertical cylinder (the body).
func step(dt: float, head: Vector3, accel: Vector3, up: Vector3, tail: Variant = null, axis: Variant = null, radius := 0.0) -> void:
	var n := pts.size()
	var jump := head - pts[0]
	if jump.length() > 2.5:  # owner teleported: carry the chain along
		for i in n:
			pts[i] += jump
			prev[i] += jump
	for i in range(1, n):
		var v := (pts[i] - prev[i]) * 0.93
		prev[i] = pts[i]
		pts[i] += v + accel * dt * dt
	for it in 5:
		pts[0] = head
		if tail != null:
			pts[n - 1] = tail
		for i in range(1, n):
			var d := pts[i] - pts[i - 1]
			var l := d.length()
			if l < 0.0001:
				continue
			if tail == null:
				pts[i] = pts[i - 1] + d / l * seg
			elif l > seg:  # rope: may hang slack but never stretches
				var corr := d * (1.0 - seg / l) * 0.5
				if i > 1:
					pts[i - 1] += corr
				if i < n - 1:
					pts[i] -= corr
		if axis != null:
			var ax: Vector3 = axis
			for i in range(1, n):
				var h := Vector2(pts[i].x - ax.x, pts[i].z - ax.z)
				var hl := h.length()
				if hl < radius and hl > 0.001:
					h = h / hl * radius
					pts[i] = Vector3(ax.x + h.x, pts[i].y, ax.z + h.y)
	for i in meshes.size():
		var a := pts[i]
		var d := pts[i + 1] - a
		if d.length() < 0.001:
			continue
		var u := up
		if absf(d.normalized().dot(u)) > 0.95:
			u = Vector3.RIGHT if absf(d.normalized().x) < 0.9 else Vector3.FORWARD
		meshes[i].global_transform = Transform3D(Basis.looking_at(d, u), a + d * 0.5)


func point_at(t: float) -> Vector3:
	var f := clampf(t, 0.0, 1.0) * (pts.size() - 1)
	var i := mini(int(f), pts.size() - 2)
	return pts[i].lerp(pts[i + 1], f - i)


## A rider's weight: drags the nearest point down a little each frame.
func weigh(t: float, amount: float) -> void:
	var i := clampi(roundi(t * (pts.size() - 1)), 1, pts.size() - 2)
	pts[i] += Vector3(0, -amount, 0)
