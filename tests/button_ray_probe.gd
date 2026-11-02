## Where does a desktop crosshair end up when it aims at the capsule's screen?
##   godot --headless --path RetroXR res://mods/xenu.synth_rift/tests/button_ray_probe.tscn
extends Node

const SCENE := "res://mods/xenu.synth_rift/scenes/rift_summoner.tscn"


var _failed := 0


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	var pod: RigidBody3D = (load(SCENE) as PackedScene).instantiate()
	add_child(pod)
	pod.freeze = true
	for i in 6:
		await get_tree().physics_frame
	var button := pod.get_node("SummonButton") as Node3D
	var centre := button.global_position
	print("[probe] button at ", centre, " layer=", (button as CollisionObject3D).collision_layer)
	# Aim from a person's eye, 1.2 m back along the button's own normal, and from straight in front.
	var n := button.global_basis.y
	for label: String in ["normal", "front", "front_left"]:
		var from := centre + n * 1.2
		if label == "front":
			from = Vector3(0, 1.6, 2.2)
		elif label == "front_left":
			from = Vector3(-0.5, 1.6, 2.2)
		var to := centre + (centre - from).normalized() * 0.5
		var t := InteractionResolver.resolve_desktop(pod.get_world_3d().direct_space_state, from, to, null)
		var ok: bool = t.kind == InteractionTarget.KIND_BUTTON and t.action_node == button
		print("[probe] ", "PASS " if ok else "FAIL ", label, " from ", from, " -> kind=", t.kind, " hit=", t.hit_node)
		if not ok:
			_failed += 1
	print("[probe] failed=", _failed)
	get_tree().quit(1 if _failed > 0 else 0)
