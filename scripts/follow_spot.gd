## FollowSpot -- where Synth appears when they follow the player into a room ("follow me").
##
## Beside the player, not out of a capsule: on their right if there is room, else their left, and then ever further round
## to the shoulders and behind them, then ahead, nearest first (a ring a hand's width from them, then wider). A spot
## counts when there is floor and room for a body on it, and nothing solid between it and the player (not on the other
## side of a wall or a shelf).
##
## Pure of the physics world: `free` and `clear` are Callables, so the headless suite draws its own rooms (the Summoner
## hands it ones that ask the physics space). Static and node-free like the other views.
extends RefCounted

## How far from the player's feet, nearest ring first. The first is an arm's length: close enough to be "beside".
const RINGS := [0.8, 1.1, 1.5, 2.0]
## Degrees from straight ahead, positive to the right. Hips first, then the shoulders (behind the hips), then behind,
## and only then the front: what appears in front of someone is in the way of what they are looking at.
const ANGLES := [90.0, -90.0, 135.0, -135.0, 180.0, 45.0, -45.0, 0.0]


## Every spot to try, in the order to try it: ring by ring, and in a ring by ANGLES.
static func candidates(player: Vector3, forward: Vector3) -> Array:
	var fwd := Vector3(forward.x, 0.0, forward.z)
	fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3(0.0, 0.0, -1.0)
	var right := fwd.cross(Vector3.UP).normalized()
	var out: Array = []
	for ring: float in RINGS:
		for deg: float in ANGLES:
			var a := deg_to_rad(deg)
			out.append(player + (fwd * cos(a) + right * sin(a)) * ring)
	return out


## {ok, pos, facing}: the first candidate `free(pos) -> bool` accepts and `clear(player, pos) -> bool` can be seen from
## the player. `pos` is where `free` left it (it may move the spot onto the floor under it); `facing` is the flat
## direction from there to the player, which is where Synth turns to. ok is false when nothing is free.
static func pick(player: Vector3, forward: Vector3, free: Callable, clear: Callable) -> Dictionary:
	for spot: Vector3 in candidates(player, forward):
		var verdict: Variant = free.call(spot)
		# null / false: not here. A Vector3: here, on the floor at that point. true: here, as it is.
		if verdict == null or (verdict is bool and not verdict):
			continue
		var pos: Vector3 = verdict if verdict is Vector3 else spot
		if not bool(clear.call(player, pos)):
			continue
		var to_player := Vector3(player.x - pos.x, 0.0, player.z - pos.z)
		return {"ok": true, "pos": pos, "facing": to_player.normalized() if to_player.length() > 0.001 else -forward}
	return {"ok": false}
