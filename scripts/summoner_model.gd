## SummonerModel -- the Rift Summoner's body: a small teleportation capsule.
##
## Built in code from primitives (nothing downloaded, nothing to credit): a gunmetal
## cylinder open down its front like a booth, a hood over the opening, a glowing
## floor pad, a ribbed strip up one side and three splayed feet. The inside glows in
## the lamp colour (red off, amber waiting, green open), the colour the Summoner's
## status already uses, plus a beam that only stands while the rift is open.
##
## The front is -Z, the way Synth steps out. Everything is a DIRECT child of the host,
## because PickableHighlight outlines its parent's direct MeshInstance3D children.
extends RefCounted

## The figure-stand in the reference picture is about 0.3 m tall; this is a pod a person
## stands in, so everything is that many times bigger. One number to change if it is too much.
const SIZE := 6.5
const HEIGHT := 0.30 * SIZE
const R_OUT := 0.07 * SIZE
const R_IN := 0.058 * SIZE
## Half the width of the opening, from straight ahead, in degrees.
const OPEN_HALF_DEG := 52.0
const BASE_Y := -0.15 * SIZE
## The whole thing stands this tall, feet included: y = 0 is the middle of it.
const FLOOR_Y := -0.17 * SIZE
const SYNTH_CYAN := Color(0.43, 1.0, 1.0)
## The screen is a hand-sized thing whatever the pod is: 12 x 7 cm, at about the height of
## a standing person's chest, on the pod's front just to the right of the opening.
const SCREEN_SIZE := Vector2(0.12, 0.07)
const SCREEN_HEIGHT_ABOVE_FLOOR := 1.25
const SCREEN_AT_DEG := 72.0
const SCREEN_TILT_DEG := 15.0


## Build every part under `host`. Returns {lamp: [MeshInstance3D], beam: MeshInstance3D}.
static func build(host: Node3D) -> Dictionary:
	var shell_mat := StandardMaterial3D.new()
	shell_mat.albedo_color = Color(0.2, 0.21, 0.24)
	shell_mat.metallic = 0.75
	shell_mat.roughness = 0.38
	shell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = SYNTH_CYAN
	trim_mat.emission_enabled = true
	trim_mat.emission = SYNTH_CYAN
	trim_mat.emission_energy_multiplier = 1.2

	var y0 := BASE_Y + 0.02 * SIZE
	var y1 := y0 + HEIGHT - 0.04 * SIZE
	var open := deg_to_rad(OPEN_HALF_DEG)

	# The wall: an arc from one edge of the opening round the back to the other.
	_part(host, "Shell", _arc_shell(R_OUT, R_IN, y0, y1, open, TAU - open, 64), shell_mat)

	# The hood over the opening, and the sill under it.
	_part(host, "Hood", _cylinder(R_OUT + 0.004 * SIZE, 0.035 * SIZE), shell_mat, Vector3(0, y1 + 0.0175 * SIZE, 0))
	_part(host, "Sill", _cylinder(R_OUT + 0.004 * SIZE, 0.02 * SIZE), shell_mat, Vector3(0, y0 - 0.01 * SIZE, 0))
	# The base ring the feet hang from.
	_part(host, "Base", _cylinder(0.088 * SIZE, 0.02 * SIZE), shell_mat, Vector3(0, BASE_Y - 0.01 * SIZE, 0))

	# Three splayed feet, one behind and one to each front corner, canted outward.
	for i in 3:
		var a := deg_to_rad(180.0 + 120.0 * float(i))
		var node := _part(host, "Foot%d" % i, _box(Vector3(0.05, 0.012, 0.075) * SIZE), shell_mat)
		node.position = Vector3(sin(a) * 0.098 * SIZE, FLOOR_Y + 0.016 * SIZE, -cos(a) * 0.098 * SIZE)
		node.rotation = Vector3(0, a, 0)
		node.rotate_object_local(Vector3.RIGHT, deg_to_rad(-22.0))

	# A ribbed strip up the right side, like a scale.
	_part(host, "Ribs", _ribs(), trim_mat, Vector3.ZERO)
	# Cyan lines framing the opening, down both edges.
	for side in [-1.0, 1.0]:
		var edge := _box(Vector3(0.006 * SIZE, HEIGHT - 0.05 * SIZE, 0.006 * SIZE))
		var n := _part(host, "Edge%s" % ("L" if side < 0.0 else "R"), edge, trim_mat)
		n.position = Vector3(side * sin(open) * (R_OUT + 0.001 * SIZE), (y0 + y1) * 0.5, -cos(open) * (R_OUT + 0.001 * SIZE))

	# What glows: the inside wall (named Lamp, which the Summoner colours), the floor.
	var lamp_nodes: Array[MeshInstance3D] = []
	lamp_nodes.append(_part(host, "Lamp", _arc_shell(R_IN - 0.001 * SIZE, R_IN - 0.003 * SIZE, y0, y1, open, TAU - open, 64), null))
	lamp_nodes.append(_part(host, "Pad", _cylinder(R_IN - 0.004 * SIZE, 0.006 * SIZE), null, Vector3(0, y0 + 0.003 * SIZE, 0)))

	# The screen, small, at chest height, on a bracket by the opening.
	var screen_mat := StandardMaterial3D.new()
	screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_mat.albedo_color = Color(0.9, 0.15, 0.1)
	var button := _screen_button(host, shell_mat, screen_mat)

	# The beam: a column of light, there only while the rift is open.
	var beam_mat := StandardMaterial3D.new()
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.albedo_color = Color(0.4, 1.0, 0.7, 0.35)
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var beam := _part(host, "Beam", _cylinder(0.026 * SIZE, HEIGHT - 0.07 * SIZE), beam_mat, Vector3(0, (y0 + y1) * 0.5, 0))
	beam.visible = false

	return {"lamp": lamp_nodes, "beam": beam, "beam_mat": beam_mat,
		"button": button, "screen_mat": screen_mat, "screen_label": button.get_node("Label")}


## Where the screen's face points: out from the pod at its angle, tilted a little up.
static func screen_normal() -> Vector3:
	var th := deg_to_rad(SCREEN_AT_DEG)
	var up := deg_to_rad(SCREEN_TILT_DEG)
	return Vector3(sin(th) * cos(up), sin(up), -cos(th) * cos(up))


## The screen: a VRButton (a fingertip over it in VR, the reticle's click on a desktop,
## button_pressed either way). Its cap is a thin box; the VRButton node's own +Y is the
## screen's face (out of the pod, tilted up), so "into the pod" is the cap's -Y.
static func _screen_button(host: Node3D, bracket_mat: Material, screen_mat: Material) -> Area3D:
	var n := screen_normal()
	var tangent := Vector3(cos(deg_to_rad(SCREEN_AT_DEG)), 0.0, sin(deg_to_rad(SCREEN_AT_DEG)))
	var basis := Basis(tangent, n, tangent.cross(n))
	var th := deg_to_rad(SCREEN_AT_DEG)
	var y := FLOOR_Y + SCREEN_HEIGHT_ABOVE_FLOOR
	# On the shell, standing off it by the bracket's thickness.
	var base := Vector3(sin(th) * R_OUT, y, -cos(th) * R_OUT)

	var bracket := _part(host, "Bracket", _box(Vector3(SCREEN_SIZE.x + 0.035, 0.022, SCREEN_SIZE.y + 0.035)), bracket_mat)
	bracket.transform = Transform3D(basis, base + n * 0.011)

	var button := VRButton.new()
	button.name = "SummonButton"
	button.trigger_radius = 0.04
	button.depress_depth = 0.004
	button.transform = Transform3D(basis, base + n * (0.022 + 0.003))
	var cap := MeshInstance3D.new()
	cap.name = "ButtonMesh"
	cap.mesh = _box(Vector3(SCREEN_SIZE.x, 0.006, SCREEN_SIZE.y))
	cap.material_override = screen_mat
	button.add_child(cap)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(SCREEN_SIZE.x + 0.02, 0.03, SCREEN_SIZE.y + 0.02)
	shape.shape = box
	button.add_child(shape)
	var label := Label3D.new()
	label.name = "Label"
	label.text = "SUMMON"
	label.font_size = 40
	label.pixel_size = 0.0006
	label.modulate = Color(0.06, 0.02, 0.02)
	label.shaded = false
	label.double_sided = false
	label.position = Vector3(0, 0.0045, 0)
	# The text faces the screen's normal (the button's +Y) and its top points up in the world.
	var local_up := basis.inverse() * Vector3.UP
	label.basis = Basis.looking_at(Vector3(0, -1, 0), local_up)
	button.add_child(label)
	host.add_child(button)
	return button


static func _part(host: Node3D, part_name: String, mesh: Mesh, mat: Material,
		at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	if mat != null:
		mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)
	return mi


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 48
	m.rings = 1
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## Scale ticks up the -X side (the left, clear of the screen), outside the wall: thin boxes merged into one mesh.
static func _ribs() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ticks := 16
	var span := HEIGHT - 0.09 * SIZE
	var top := BASE_Y + 0.02 * SIZE + span + 0.03 * SIZE
	for i in ticks:
		var box := BoxMesh.new()
		box.size = Vector3(0.008, 0.0045, 0.022) * SIZE
		var y := top - span * float(i) / float(ticks - 1)
		var xf := Transform3D(Basis(), Vector3(-(R_OUT + 0.003 * SIZE), y, 0.0))
		st.append_from(box, 0, xf)
	return st.commit()


## A cylindrical wall between two angles (0 = straight ahead, -Z; positive turns toward +X),
## with a flat edge at each end so the opening reads as a cut, not a sheet.
static func _arc_shell(r_out: float, r_in: float, y0: float, y1: float,
		th0: float, th1: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		var a := lerpf(th0, th1, float(i) / segs)
		var b := lerpf(th0, th1, float(i + 1) / segs)
		_strip(st, r_out, a, b, y0, y1, 1.0)   # outside
		_strip(st, r_in, a, b, y0, y1, -1.0)   # inside
		_cap(st, r_in, r_out, a, b, y1, Vector3.UP)
		_cap(st, r_in, r_out, a, b, y0, Vector3.DOWN)
	for th: float in [th0, th1]:
		var dir := 1.0 if th == th0 else -1.0
		var p0 := _pt(r_in, th, y0)
		var p1 := _pt(r_out, th, y0)
		var p2 := _pt(r_out, th, y1)
		var p3 := _pt(r_in, th, y1)
		var n := Vector3(cos(th), 0, sin(th)) * dir
		_quad(st, [p0, p1, p2, p3], [n, n, n, n])
	return st.commit()


static func _pt(r: float, th: float, y: float) -> Vector3:
	return Vector3(sin(th) * r, y, -cos(th) * r)


static func _strip(st: SurfaceTool, r: float, a: float, b: float, y0: float, y1: float, facing: float) -> void:
	var na := Vector3(sin(a), 0, -cos(a)) * facing
	var nb := Vector3(sin(b), 0, -cos(b)) * facing
	_quad(st, [_pt(r, a, y0), _pt(r, b, y0), _pt(r, b, y1), _pt(r, a, y1)], [na, nb, nb, na])


static func _cap(st: SurfaceTool, r_in: float, r_out: float, a: float, b: float, y: float, n: Vector3) -> void:
	_quad(st, [_pt(r_in, a, y), _pt(r_out, a, y), _pt(r_out, b, y), _pt(r_in, b, y)], [n, n, n, n])


## Two triangles for a quad given as four corners in order. The material is
## double-sided, so winding only has to be consistent.
static func _quad(st: SurfaceTool, p: Array, n: Array) -> void:
	for idx: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n[idx] as Vector3)
		st.add_vertex(p[idx] as Vector3)
