## Where Synth appears when they follow the player into a room: pure, over rooms the cases draw themselves.
##
##   godot --headless --path RetroXR --script res://mods/xenu.synth_rift/tests/follow_tests.gd
extends SceneTree

const FollowSpot := preload("res://mods/xenu.synth_rift/scripts/follow_spot.gd")

var _failed := 0
var _count := 0


func _init() -> void:
	_open_room()
	_crowded_room()
	_wall_between()
	_nothing_free()
	_facing()
	print("[rift-tests] %d cases, %d failed" % [_count, _failed])
	quit(1 if _failed > 0 or _count == 0 else 0)


static func _always(_p: Vector3) -> Variant:
	return true


static func _see_all(_a: Vector3, _b: Vector3) -> bool:
	return true


## Facing -Z the right is +X: an empty room puts them at the player's right hand, an arm's length away.
func _open_room() -> void:
	var r := FollowSpot.pick(Vector3.ZERO, Vector3(0, 0, -1), _always, _see_all)
	_check(r["ok"], "an empty room has room")
	var pos: Vector3 = r["pos"]
	_check(pos.distance_to(Vector3(0.8, 0, 0)) < 0.01, "beside them, on their right, 0.8 m (%s)" % str(pos))
	# Turned round, "right" is the player's right, not the world's.
	var back := FollowSpot.pick(Vector3.ZERO, Vector3(0, 0, 1), _always, _see_all)
	_check((back["pos"] as Vector3).distance_to(Vector3(-0.8, 0, 0)) < 0.01, "it follows which way they face (%s)" % str(back["pos"]))


## The right hand is taken: the left; both: the shoulders, then behind, then ahead; a ring is exhausted before the next.
func _crowded_room() -> void:
	var fwd := Vector3(0, 0, -1)
	var taken: Array = []
	var free := func(p: Vector3) -> Variant:
		for t: Vector3 in taken:
			if t.distance_to(p) < 0.3:
				return null
		return true
	taken.append(Vector3(0.8, 0, 0))
	var left: Dictionary = FollowSpot.pick(Vector3.ZERO, fwd, free, _see_all)
	_check((left["pos"] as Vector3).distance_to(Vector3(-0.8, 0, 0)) < 0.01, "the right is taken: their left")
	taken.append(Vector3(-0.8, 0, 0))
	var shoulder: Dictionary = FollowSpot.pick(Vector3.ZERO, fwd, free, _see_all)
	var sp: Vector3 = shoulder["pos"]
	_check(sp.x > 0.4 and sp.z > 0.4 and absf(sp.length() - 0.8) < 0.01, "both hips taken: the right shoulder, still the near ring (%s)" % str(sp))
	taken.append(sp)
	taken.append(Vector3(-0.8 * sin(deg_to_rad(45.0)), 0, 0.8 * cos(deg_to_rad(45.0))))
	var behind: Dictionary = FollowSpot.pick(Vector3.ZERO, fwd, free, _see_all)
	_check((behind["pos"] as Vector3).distance_to(Vector3(0, 0, 0.8)) < 0.01, "then right behind them (%s)" % str(behind["pos"]))
	# A whole ring blocked: the next ring out, not a worse spot in the first.
	var ring_blocked := func(p: Vector3) -> Variant:
		return null if p.length() < 0.9 else true
	var out: Dictionary = FollowSpot.pick(Vector3.ZERO, fwd, ring_blocked, _see_all)
	_check(absf((out["pos"] as Vector3).length() - 1.1) < 0.01, "the near ring full: the next one out (%s)" % str(out["pos"]))


## A spot behind a wall is not beside them: it is passed over whatever the floor there says.
func _wall_between() -> void:
	var see := func(_from: Vector3, to: Vector3) -> bool:
		return to.x < 0.5   # a wall at x = 0.5
	var r := FollowSpot.pick(Vector3.ZERO, Vector3(0, 0, -1), _always, see)
	_check(r["ok"] and (r["pos"] as Vector3).x < 0.5, "a spot past a wall is skipped (%s)" % str(r.get("pos")))


func _nothing_free() -> void:
	var none := func(_p: Vector3) -> Variant: return null
	_check(not FollowSpot.pick(Vector3.ZERO, Vector3(0, 0, -1), none, _see_all)["ok"], "a room with no room says so, so the pod's own front is used")
	# free() may move the spot onto the floor under it.
	var lift := func(p: Vector3) -> Variant: return p + Vector3(0, 0.2, 0)
	_check(is_equal_approx((FollowSpot.pick(Vector3.ZERO, Vector3(0, 0, -1), lift, _see_all)["pos"] as Vector3).y, 0.2), "the spot is where free() put it")
	# Looking up or down gives no heading of its own: it must not divide by zero.
	_check(FollowSpot.pick(Vector3.ZERO, Vector3.DOWN, _always, _see_all)["ok"], "straight down still has a heading")


## They turn to the player where they stand.
func _facing() -> void:
	var r := FollowSpot.pick(Vector3(2, 0, 3), Vector3(0, 0, -1), _always, _see_all)
	var d: Vector3 = (Vector3(2, 0, 3) - (r["pos"] as Vector3)).normalized()
	_check((r["facing"] as Vector3).distance_to(d) < 0.01, "they face the player (%s)" % str(r["facing"]))


func _check(ok: bool, what: String) -> void:
	_count += 1
	if not ok:
		_failed += 1
		print("FAIL: %s" % what)
