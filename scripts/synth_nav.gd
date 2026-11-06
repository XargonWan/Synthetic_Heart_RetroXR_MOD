## SynthNav -- a way round things for Synth's body.
##
## No room has a navmesh, and baking one at run time for a room that changes every time the player moves a console is
## the wrong tool: this is an A* over a grid laid on the floor around them, where a cell is asked of the PHYSICS WORLD
## only when the search reaches it (a walk across an empty room asks about thirty cells; going round a wall a few
## hundred; the search is capped, and when it is, or when no way exists, the answer is the nearest it got and says so).
##
## A cell is blocked when a cylinder a little wider than they are, from `LIFT` above the floor to head height, touches
## something their body would collide with. Things lower than `LIFT` are left to their capsule, whose round foot rides over
## a cartridge or a cable; anything taller is a wall to them. Pure of the body: `blocked_fn` can be replaced, which is
## how `nav_tests` checks the search on a map it drew itself.
extends RefCounted

const CELL := 0.2
## Their capsule is 0.22 wide; the rest is room to turn a corner without rubbing it.
const RADIUS := 0.30
const HEIGHT := 1.4
const LIFT := 0.10
## Physics questions one search may ask.
const MAX_QUERIES := 1800
## A long walk with no leash (an exploration leg) is searched on the coarse grid, with more questions allowed.
const FREE_MAX_QUERIES := 4000
var max_queries := MAX_QUERIES
## Layers they collide with: the world, and the pickable things (a console, a box, a seat).
const MASK := (1 << 0) | (1 << 2)

## Callable(Vector3 centre) -> bool. Replaced by the tests; by default it asks `space`.
var blocked_fn: Callable = _physics_blocked
var space: PhysicsDirectSpaceState3D = null
var mask := MASK
var exclude: Array[RID] = []
var floor_y := 0.0
## Their leash: a cell farther than `leash` from `anchor` is out of bounds.
var anchor := Vector3.ZERO
var leash := 6.0

## Places a walk already failed at: a cell near one is blocked, so a second try goes another way.
var avoid: Array[Vector3] = []
const AVOID_RADIUS := 0.4

## Cell size: 0.2 for a walk; a survey of a whole room uses a coarser grid (`SURVEY_CELL`) to ask fewer questions.
var cell_size := CELL
const SURVEY_CELL := 0.4

## Something to keep clear of that is not in the physics world's static shapes: the player (who moves), a thing rolling.
## Each is {"pos": Vector3, "r": float}; a cell whose centre is inside one is blocked.
var discs: Array = []

## Without a leash a cell can be over the edge of the world: when set, a cell needs a floor within `STEP` of their feet
## or it is blocked (a ledge, a stair down, a hole). Off for the old walks, which are leashed to a room they know.
var check_ground := false
const STEP := 0.3
const GROUND_MASK := 1 << 0
## Callable(Vector3 centre) -> bool (is there floor under it). Replaced by the tests; by default it asks `space`.
var ground_fn: Callable = _physics_ground

var queries := 0
var _cache: Dictionary = {}
var _shape: CylinderShape3D = null


## {path: PackedVector3Array (world points, start not included), complete: bool, queries: int}. `complete` is false
## when the path stops short of `to` (the nearest cell the search reached): the caller decides what that means.
func plan(from: Vector3, to: Vector3) -> Dictionary:
	_cache.clear()
	queries = 0
	var start := _cell_of(from)
	var goal := _cell_of(to)
	# Where they stand is free by definition: they are there, and a thing touching their margin must not trap them.
	_cache[start] = false
	var goal_blocked := _blocked(goal)
	# A goal in something (a point in a console's middle) is reached when the path gets within a few cells of it.
	var tolerance := 0 if not goal_blocked else 2
	if start == goal:
		return {"path": PackedVector3Array([to]), "complete": true, "queries": queries}

	var g: Dictionary = {start: 0.0}
	var parent: Dictionary = {}
	var closed: Dictionary = {}
	var heap_f: Array[float] = []
	var heap_k: Array[Vector2i] = []
	_push(heap_f, heap_k, _h(start, goal), start)
	var best := start
	var best_h := _h(start, goal)
	var found := false
	var cap_hit := false
	while not heap_k.is_empty():
		var cur := _pop(heap_f, heap_k)
		if closed.has(cur):
			continue
		closed[cur] = true
		var h := _h(cur, goal)
		if h < best_h:
			best_h = h
			best = cur
		if maxi(absi(cur.x - goal.x), absi(cur.y - goal.y)) <= tolerance and (cur == goal or goal_blocked):
			best = cur
			found = true
			break
		if queries >= max_queries:
			cap_hit = true
			break
		for d: Vector2i in _DIRS:
			var nxt := cur + d
			if closed.has(nxt) or not _in_bounds(nxt):
				continue
			if _blocked(nxt):
				continue
			var diagonal := d.x != 0 and d.y != 0
			# No cutting a corner: both cells beside a diagonal step must be free too.
			if diagonal and (_blocked(Vector2i(cur.x + d.x, cur.y)) or _blocked(Vector2i(cur.x, cur.y + d.y))):
				continue
			var ng: float = float(g[cur]) + (1.4142 if diagonal else 1.0)
			if not g.has(nxt) or ng < float(g[nxt]):
				g[nxt] = ng
				parent[nxt] = cur
				_push(heap_f, heap_k, ng + _h(nxt, goal), nxt)

	var cells: Array[Vector2i] = []
	var at := best
	while at != start:
		cells.append(at)
		at = parent[at]
	cells.reverse()
	var points := PackedVector3Array()
	for c: Vector2i in cells:
		points.append(_centre_of(c))
	var complete := found
	if found and not goal_blocked and not points.is_empty():
		points[points.size() - 1] = Vector3(to.x, floor_y, to.z)
	points = _pulled(Vector3(from.x, floor_y, from.z), points)
	return {"path": points, "complete": complete, "queries": queries, "capped": cap_hit}


## Is there nothing in the way along a straight line? (Used to pull the path straight: the grid's own path zig-zags.)
func clear_line(a: Vector3, b: Vector3) -> bool:
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var steps := maxi(1, int(ceil(flat.length() / (cell_size * 0.5))))
	for i in range(1, steps + 1):
		var p := a + flat * (float(i) / float(steps))
		if _blocked(_cell_of(p)):
			return false
	return true


## String-pulling: from each point, the farthest later point in a straight clear line; the points between go.
func _pulled(from: Vector3, points: PackedVector3Array) -> PackedVector3Array:
	if points.size() <= 1:
		return points
	var out := PackedVector3Array()
	var here := from
	var i := 0
	while i < points.size():
		var far := i
		for j in range(points.size() - 1, i - 1, -1):
			if clear_line(here, points[j]):
				far = j
				break
		out.append(points[far])
		here = points[far]
		i = far + 1
	return out


# ── what can be walked to: an incremental Dijkstra ───────────────────────────
#
# `plan` answers "is there a way to HERE". A survey asks the other question -- "where is there a way to" -- and a room is
# a few thousand cells, so it is searched a few hundred physics questions at a time (`reach_step`, one call per frame)
# and not in one frame. The cost of each cell is the length of the way to it, in metres.

class ReachState:
	var start := Vector2i.ZERO
	var g: Dictionary = {}
	var closed: Dictionary = {}
	var hf: Array[float] = []
	var hk: Array[Vector2i] = []
	var done := false
	var capped := false


func reach_begin(from: Vector3) -> ReachState:
	_cache.clear()
	queries = 0
	var st := ReachState.new()
	st.start = _cell_of(from)
	_cache[st.start] = false
	st.g[st.start] = 0.0
	_push(st.hf, st.hk, 0.0, st.start)
	return st


## Search until `budget` more physics questions have been asked, or `max_cells` cells are settled. True when done.
func reach_step(st: ReachState, budget: int, max_cells: int) -> bool:
	var q0 := queries
	while not st.hk.is_empty():
		if queries - q0 >= budget:
			return false
		var cur := _pop(st.hf, st.hk)
		if st.closed.has(cur):
			continue
		st.closed[cur] = true
		if st.closed.size() >= max_cells:
			st.capped = true
			st.done = true
			return true
		for d: Vector2i in _DIRS:
			var nxt := cur + d
			if st.closed.has(nxt) or not _in_bounds(nxt) or _blocked(nxt):
				continue
			var diagonal := d.x != 0 and d.y != 0
			if diagonal and (_blocked(Vector2i(cur.x + d.x, cur.y)) or _blocked(Vector2i(cur.x, cur.y + d.y))):
				continue
			var ng: float = float(st.g[cur]) + (1.4142 if diagonal else 1.0)
			if not st.g.has(nxt) or ng < float(st.g[nxt]):
				st.g[nxt] = ng
				_push(st.hf, st.hk, ng, nxt)
	st.done = true
	return true


## {cell: metres of way} for every settled cell (the start included, at 0).
func reach_cells(st: ReachState) -> Dictionary:
	var out: Dictionary = {}
	for c: Vector2i in st.closed.keys():
		out[c] = float(st.g[c]) * cell_size
	return out


# ── the grid ─────────────────────────────────────────────────────────────────

const _DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x / cell_size), roundi(p.z / cell_size))


func _centre_of(c: Vector2i) -> Vector3:
	return Vector3(float(c.x) * cell_size, floor_y, float(c.y) * cell_size)


## Where a cell is, for a caller that searched with `reach_*`.
func centre_of(c: Vector2i) -> Vector3:
	return _centre_of(c)


## Where they stand is free by definition, whatever touches their margin: say so before asking about a line from here.
func mark_free(p: Vector3) -> void:
	_cache[_cell_of(p)] = false


func _in_bounds(c: Vector2i) -> bool:
	var p := _centre_of(c)
	return Vector2(p.x - anchor.x, p.z - anchor.z).length() <= leash + 1.0


func _h(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return float(maxi(dx, dy)) + 0.4142 * float(mini(dx, dy))


func _blocked(c: Vector2i) -> bool:
	if _cache.has(c):
		return _cache[c]
	var centre := _centre_of(c)
	for a: Vector3 in avoid:
		if Vector2(a.x - centre.x, a.z - centre.z).length() < AVOID_RADIUS:
			_cache[c] = true
			return true
	for d: Dictionary in discs:
		var dp: Vector3 = d["pos"]
		if Vector2(dp.x - centre.x, dp.z - centre.z).length() < float(d["r"]):
			_cache[c] = true
			return true
	queries += 1
	var hit: bool = blocked_fn.call(centre)
	if not hit and check_ground:
		queries += 1
		hit = not bool(ground_fn.call(centre))
	_cache[c] = hit
	return hit


func _physics_ground(centre: Vector3) -> bool:
	if space == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(centre + Vector3(0.0, STEP + 0.05, 0.0), centre - Vector3(0.0, STEP + 0.05, 0.0))
	q.collision_mask = GROUND_MASK
	q.exclude = exclude
	return not space.intersect_ray(q).is_empty()


func _physics_blocked(centre: Vector3) -> bool:
	if space == null:
		return false
	if _shape == null:
		_shape = CylinderShape3D.new()
		_shape.radius = RADIUS
		_shape.height = HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape
	q.transform = Transform3D(Basis.IDENTITY, centre + Vector3(0.0, LIFT + HEIGHT * 0.5, 0.0))
	q.collision_mask = mask
	q.exclude = exclude
	return not space.intersect_shape(q, 1).is_empty()


# ── a binary min-heap of (f, cell) ───────────────────────────────────────────

func _push(hf: Array[float], hk: Array[Vector2i], f: float, k: Vector2i) -> void:
	hf.append(f)
	hk.append(k)
	var i := hf.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if hf[p] <= hf[i]:
			break
		var tf := hf[p]
		hf[p] = hf[i]
		hf[i] = tf
		var tk := hk[p]
		hk[p] = hk[i]
		hk[i] = tk
		i = p


func _pop(hf: Array[float], hk: Array[Vector2i]) -> Vector2i:
	var top := hk[0]
	var last := hf.size() - 1
	hf[0] = hf[last]
	hk[0] = hk[last]
	hf.resize(last)
	hk.resize(last)
	var i := 0
	var n := hf.size()
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var m := i
		if l < n and hf[l] < hf[m]:
			m = l
		if r < n and hf[r] < hf[m]:
			m = r
		if m == i:
			break
		var tf := hf[m]
		hf[m] = hf[i]
		hf[i] = tf
		var tk := hk[m]
		hk[m] = hk[i]
		hk[i] = tk
		i = m
	return top
