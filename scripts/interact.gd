class_name Interact
## What's within reach and what you can do with it: the one place that decides.
## The client uses it for the prompt and the hold-E wheel; the server runs the
## same code to check a request before carrying it out, so they always agree.
##
## A target is {kind, id, pos, title}. An action is {verb, label, ok, why, key}.
## To make something new interactive, teach `target` to find it, list its
## actions here, and handle the verb in main.actions._do_action.

const NONE := Vector2i(-1, -1)
const PICKUP_REACH := 14.0
const CONTAINER_REACH := 20.0
const TRAP_REACH := 12.0
const STOMP_REACH := 18.0
const DOOR_REACH := 24.0  # (the prompt shows a step before you touch it)


## The thing E would act on for player `p`, or {} if nothing is in reach.
## Everything in reach competes: the closest wins, with a nudge toward what
## you're facing, and a door you're standing in always wins.
static func target(main: Node, p: Player) -> Dictionary:
	var w: World = main.world
	var cands := _candidates(main, p)
	var best := {}
	var best_score := INF
	var facing := p.aim.normalized()
	for t in cands:
		var to: Vector2 = t.pos - p.position
		var score := to.length() - 6.0 * (facing.dot(to.normalized()) if to.length() > 0.5 else 1.0)
		if t.kind == "door" and w.door_overlap(t.id, p.position) == 2:
			score = -100.0
		if t.kind == "car" and p.on_car < 0:
			score += 14.0  # (climbing is rarely what E beside a car means: a bike or a door by it comes first)
		if score < best_score:
			best_score = score
			best = t
	return best


static func _candidates(main: Node, p: Player) -> Array:
	var w: World = main.world
	var out := []
	var st := stairs_near(w, p.position)
	if st != NONE:
		out.append({kind = "stairs", id = st, pos = w.to_pos(st), title = "บันได"})
	if p.on_car >= 0:
		# On a car roof: only getting down again.
		out.append({kind = "car", id = p.on_car, pos = p.position + Vector2(0, 1), title = "หลังคารถ"})
		return out
	_hurt_players(main, p, out)
	if p.storey > 0:
		# Upstairs: the stairs, and what's up here with you.
		for pid in main.pickups:
			var pos: Vector2 = main.pickups[pid].pos
			if main.pickups[pid].get("storey", 0) == p.storey and p.position.distance_to(pos) < PICKUP_REACH:
				out.append({kind = "pickup", id = pid, pos = pos, title = Items.display_name(main.pickups[pid].item.id)})
		for z: Zombie in main.zombies.values():
			if z.storey == p.storey and (z.flags & 2 or z.crawler()) and not (z.flags & 16 and z.kind == "faker") and p.position.distance_to(z.position) < STOMP_REACH:
				out.append({kind = "zombie", id = z.zid, pos = z.position, title = "ซอมบี้ล้มอยู่"})
		for f in w.near(p.position):
			if f is FurnitureProp and f.data.get("storey", 0) == p.storey and p.position.distance_to(f.position) < CONTAINER_REACH and w.building_at.get(f.data.cell) == w.building_at.get(w.to_cell(p.position)):
				out.append({kind = "container", id = f.data.id, pos = f.position, title = container_title(f.data.kind)})
		_things(w, p, out)
		_corpses(main, p, out)
		_remains(main, p, out)
		_seats(w, p, w.building_at.get(w.to_cell(p.position)), out)
		return out
	if p.on_roof:
		# Up top only the stairs and the roof edge are in reach.
		if Interact.jump_spot(w, p.position) != Vector2.INF:
			out.append({kind = "edge", id = 0, pos = p.position + Vector2(0, 1), title = "ขอบหลังคา"})
		return out
	for pid in main.pickups:
		var pos: Vector2 = main.pickups[pid].pos
		if p.position.distance_to(pos) < PICKUP_REACH and main.pickups[pid].get("storey", 0) == 0:
			out.append({kind = "pickup", id = pid, pos = pos, title = Items.display_name(main.pickups[pid].item.id)})
	# A zombie knocked flat right at your feet: finish it.
	for z: Zombie in main.zombies.values():
		if (z.flags & 2 or z.crawler()) and not (z.flags & 16 and z.kind == "faker") and z.storey == 0 and p.position.distance_to(z.position) < STOMP_REACH:
			out.append({kind = "zombie", id = z.zid, pos = z.position, title = "ซอมบี้ล้มอยู่"})
	var trap := trap_near(w, p.position)
	if trap >= 0:
		out.append({kind = "trap", id = trap, pos = w.to_pos(w.doors[trap].cell), title = World.BUILDS[w.doors[trap].kind].name})
	var door := w.door_near(p.position, DOOR_REACH)
	if door >= 0 and not w.is_built(door):
		var d: Dictionary = w.doors[door]
		var win := w.is_window(door)
		var title := "ประตูเหล็กม้วน" if d.kind == "shutter" else "ประตู"
		if win:
			title = "หน้าต่างแตก · ปีนผ่านได้" if not d.closed else "หน้าต่าง"
		elif d.broken:
			title = "ประตูเหล็กถูกงัด · มุดผ่านได้" if d.kind == "shutter" else "ประตูพัง"
		out.append({kind = "window" if win else "door", id = door, pos = w.to_pos(d.cell), title = title})
	for v in w.vehicles:
		if (v.rider == 0 or v.pillion == 0) and v.rider != p.peer_id and p.position.distance_to(v.pos) < Vehicles.reach_of(v):
			out.append({kind = "vehicle", id = v.id, pos = v.pos + Vector2(0, -8), title = Vehicles.title_of(v)})
	var here: BuildingProp = w.building_at.get(w.to_cell(p.position))
	_things(w, p, out)
	_corpses(main, p, out)
	_remains(main, p, out)
	# At the edge of a canal (or any water): scoop some up, or drink it as it is.
	var wc := water_near(w, p.position)
	if wc != NONE:
		out.append({kind = "canal", id = 0, pos = w.to_pos(wc), title = "น้ำคลอง"})
	for e in w.exits:
		var r: Rect2i = e.rect
		if Rect2(r.position * World.TILE, r.size * World.TILE).grow(12.0).has_point(p.position) and p.storey == 0:
			out.append({kind = "exit", id = e.id, pos = p.position + Vector2(0, -2), title = "ทางไป" + Zones.name_of(e.to)})
	for n in w.near(p.position):
		if n is StreetProp and n.data.kind in StreetProp.CLIMB and p.storey == 0 and not n.data.get("moved", false) \
				and p.position.distance_to(StreetProp.middle(n.data)) < CAR_REACH:
			out.append({kind = "car", id = n.data.id, pos = StreetProp.middle(n.data), title = "รถ"})
	_seats(w, p, here, out)
	for f in w.near(p.position):
		# Furniture in the same building as you: no reaching through walls.
		if f is FurnitureProp and p.position.distance_to(f.position) < CONTAINER_REACH and w.building_at.get(f.data.cell) == here and f.data.get("storey", 0) == 0:
			out.append({kind = "container", id = f.data.id, pos = f.position, title = container_title(f.data.kind)})
	return out


const FRIEND_REACH := 16.0


## Another survivor beside you who's hurt (their health shows on every screen:
## what's wrong, only the server knows).
static func _hurt_players(main: Node, p: Player, out: Array) -> void:
	if not Skills.has(p, "treat_other"):
		return  # (no use pointing at a friend you can't help)
	for q: Player in main.players.values():
		if q != p and q.alive() and q.storey == p.storey and q.hp < 100.0 and p.position.distance_to(q.position) < FRIEND_REACH:
			out.append({kind = "player", id = q.peer_id, pos = q.position, title = q.pname})


## Bodies on your floor you could burn.
static func _corpses(main: Node, p: Player, out: Array) -> void:
	for cid in main.corpse_nodes:
		var cn: Corpse = main.corpse_nodes[cid]
		if is_instance_valid(cn) and cn.storey == p.storey and cn.burn < 0.0 and p.position.distance_to(cn.position) < CORPSE_REACH:
			out.append({kind = "corpse", id = cid, pos = cn.position + Vector2(cn.fall_dir * 8.0, -4), title = cn.title()})


## A dead survivor's things where they fell (Remains), on your floor.
static func _remains(main: Node, p: Player, out: Array) -> void:
	for rid in main.remains.seen:
		var r: Dictionary = main.remains.seen[rid]
		if r.storey == p.storey and p.position.distance_to(r.pos) < Remains.REACH:
			out.append({kind = "remains", id = rid, pos = r.pos, title = main.remains.title(rid)})


## Sofas, benches and chairs on your floor, in the building you are in.
static func _seats(w: World, p: Player, here: BuildingProp, out: Array) -> void:
	for d in w.near(p.position):
		if d is DecorProp and d.data.kind in SEATS and d.data.get("storey", 0) == p.storey and p.position.distance_to(d.position) < CONTAINER_REACH \
				and w.building_at.get(d.data.cell) == here:
			out.append({kind = "seat", id = d.data.id, pos = d.position, title = SEATS[d.data.kind]})


## Rebuild a target the client asked about, if it is still in reach of `p`.
static func resolve(main: Node, p: Player, kind: String, id: Variant) -> Dictionary:
	for t in _candidates(main, p):
		if t.kind == kind and t.id == id:
			return t
	return {}


## Everything that can be done with target `t` right now, in wheel order.
static func actions(main: Node, p: Player, t: Dictionary) -> Array:
	var w: World = main.world
	var out := []
	match t.get("kind", ""):
		"stairs":
			# Stairs go up floor by floor (as far as this stairwell reaches), and on up to the roof.
			var above: bool = w.storey_map(p.storey + 1).has(t.id)
			if p.on_roof:
				var top := w.top_storey(t.id)
				out.append(_act("down", "ลงชั้น %d" % (top + 1) if top > 0 else "ลงบันได"))
			elif p.storey > 0:
				out.append(_act("up", "ขึ้นชั้น %d" % (p.storey + 2) if above else "ขึ้นดาดฟ้า"))
				out.append(_act("down", "ลงชั้นล่าง" if p.storey == 1 else "ลงชั้น %d" % p.storey))
			else:
				out.append(_act("up", "ขึ้นชั้น 2" if above else "ขึ้นดาดฟ้า"))
		"edge":
			out.append(_act("jump", "กระโดดลง (เจ็บ · เสียงดัง)"))
		"pickup":
			var item: Dictionary = main.pickups[t.id].item
			out.append(_act("take", "เก็บ " + Items.display_name(item.id)))
		"trap":
			out.append(_act("take_trap", "เก็บ" + t.title + "คืน"))
		"door":
			var d: Dictionary = w.doors[t.id]
			if d.kind == "shutter":
				if not d.broken:
					out.append(_act("close", "ดึงประตูเหล็กลง (เสียงดัง)") if not d.closed else _act("open", "ดึงประตูเหล็กขึ้น (เสียงดัง)"))
				else:
					out.append(_act("repair", "ดัดประตูเหล็กกลับ (เศษเหล็ก %d · ค้อน)" % SHUTTER_SCRAP, can_fix_shutter(p),
							"ต้องมีเศษเหล็ก %d ชิ้นกับค้อน" % SHUTTER_SCRAP, "R"))
			elif d.broken:
				out.append(_act("repair", "ซ่อมประตู (ไม้ 1 แผ่น)", has_wood(p), "ต้องมีไม้กระดาน", "R"))
			else:
				if d.closed:
					out.append(_act("open", "เปิดประตู"))
				else:
					var blocked := w.door_overlap(t.id, p.position) == 2
					out.append(_act("close", "ปิดประตู", not blocked, "ถอยออกจากช่องประตูก่อนปิด"))
				out.append(_board(p, d))
		"window":
			var d: Dictionary = w.doors[t.id]
			if d.closed and d.boards == 0:
				out.append(_act("smash", "ทุบกระจก (เสียงดัง)"))
			if not d.closed:
				out.append(_act("board", "ตอกไม้ปิดหน้าต่าง", has_wood(p), "ต้องมีไม้กระดาน", "R"))
			else:
				out.append(_board(p, d))
		"thing":
			out.append_array(main.things.actions_for(p, t.id))
		"container":
			if w.container_nodes[t.id].searched:
				out.append(_act("look", "เปิดดู"))
			else:
				out.append(_act("search", "ค้นหา"))
			var f: FurnitureProp = w.container_nodes[t.id]
			if f.stripped:
				out.append(_act("strip", "รื้อไปแล้ว", false, "เหลือแต่ซาก"))
			else:
				out.append(_act("strip", "รื้อเอาไม้ ตะปู เหล็ก (เสียงดัง)"))
			if w.container_nodes[t.id].data.kind == "bed":
				var why: String = main.survival.can_sleep(p)
				out.append(_act("sleep", "นอนพัก", why == "", why))
				if p.bed == t.id:
					out.append(_act("claim", "เตียงประจำของคุณ", false, "ตื่นที่นี่เมื่อตายอยู่แล้ว"))
				else:
					out.append(_act("claim", "ตั้งเป็นเตียงประจำ (ตายแล้วตื่นที่นี่)"))
		"zombie":
			out.append(_act("stomp", "เหยียบหัวให้ตาย"))
		"exit":
			var ex: Array = w.exits.filter(func(e): return e.id == t.id)
			if not ex.is_empty():
				out.append(_act("travel", "เดินทางไป%s" % Zones.name_of(ex[0].to), Zones.open(ex[0].to), "ยังไปไม่ได้ (ย่านนี้ยังไม่เปิด)"))
		"remains":
			out.append(_act("reclaim", "เก็บของคืนทั้งหมด", main.remains.can_take(p, t.id), "ของของคนอื่น · เจ้าของเท่านั้นที่เก็บได้"))
		"corpse":
			var fire := p.inv.any(func(it): return it != null and Items.has_tag(it.id, "fire"))
			out.append(_act("burn", "จุดไฟเผาศพ", fire, "ต้องมีไฟแช็กหรือไม้ขีดไฟ"))
		"car":
			if p.on_car >= 0:
				out.append(_act("jumpdown", "กระโดดลง (ทางที่หัน)"))
			else:
				var busy: bool = main.players.values().any(func(q): return q != p and q.on_car == t.id)
				out.append(_act("climb", "ปีนขึ้นหลังคารถ", not busy, "มีคนอยู่บนรถแล้ว"))
		"canal":
			var room: bool = main.things._room_for(p, "canal")
			out.append(_act("scoop", "ตักน้ำคลองใส่ขวด/หม้อ", room, "ไม่มีขวดหรือหม้อที่ว่าง"))
			out.append(_act("gulp", "ดื่มน้ำคลอง (เสี่ยงท้องเสียมาก)", p.thirst < 98.0, "ยังไม่กระหาย"))
		"seat":
			var taken: bool = main.players.values().any(func(q): return q != p and q.sitting == t.id)
			out.append(_act("sit", "นั่งพัก", not taken, "มีคนนั่งอยู่"))
		"vehicle":
			out.append_array(main.vehicles.actions_for(p, t.id))
		"player":
			var bandages: bool = p.inv.any(func(it): return it != null and it.id in ["bandage", "firstaid"])
			out.append(_act("treat_other", "พันแผลให้ " + t.title, bandages, "ไม่มีผ้าพันแผล"))
	return out


## The action E does on a tap: the first one that can be done.
static func primary(list: Array) -> Dictionary:
	for a in list:
		if a.ok:
			return a
	return list[0] if not list.is_empty() else {}


static func find_action(list: Array, verb: String) -> Dictionary:
	for a in list:
		if a.verb == verb:
			return a
	return {}


static func _act(verb: String, label: String, ok := true, why := "", key := "") -> Dictionary:
	return {verb = verb, label = label, ok = ok, why = why if not ok else "", key = key}


static func _board(p: Player, d: Dictionary) -> Dictionary:
	var full: bool = d.boards >= World.MAX_BOARDS
	return _act("board", "ตอกไม้ (%d/%d)" % [d.boards, World.MAX_BOARDS], has_wood(p) and not full,
			"ตอกเต็มแล้ว" if full else "ต้องมีไม้กระดาน", "R")


const SHUTTER_SCRAP := 2  # scrap a bent shutter section takes to hammer straight


static func can_fix_shutter(p: Player) -> bool:
	var scrap := 0
	for it in p.inv:
		if it != null and it.id == "scrap":
			scrap += it.n
	return scrap >= SHUTTER_SCRAP and p.inv.any(func(it): return it != null and it.id == "hammer")


static func has_wood(p: Player) -> bool:
	return p.inv.any(func(it): return it != null and it.id == "wood")


const CAR_REACH := 34.0  # how near a car's middle you climb from
const CORPSE_REACH := 20.0
const CANAL_REACH := 20.0  # from the middle of a water cell: standing at its edge


## What you can sit on, and what it's called.
const SEATS := {sofa = "โซฟาไม้", bench = "ม้านั่ง", chairs = "เก้าอี้พลาสติก", barberchair = "เก้าอี้ตัดผม",
		recliner = "เก้าอี้นวดเท้า"}


static func container_title(kind: String) -> String:
	return {shelf = "ชั้นวางของ", fridge = "ตู้เย็น", counter = "เคาน์เตอร์", cabinet = "ตู้",
			table = "โต๊ะ", crate = "ลัง", bed = "เตียง", glass = "ตู้กระจก", mirror = "โต๊ะกระจกตัดผม",
			toolchest = "ตู้เครื่องมือ", stall = "รถเข็นหน้าร้าน", safe = "ตู้เซฟ", pantry = "ตู้กับข้าว",
			sink = "ซิงค์ล้างจาน"}.get(kind, "ของ")


# --- Finding things in reach ---------------------------------------------------

## Taps, stoves, generators... in reach, on your floor of your building.
static func _things(w: World, p: Player, out: Array) -> void:
	var here: BuildingProp = w.building_at.get(w.to_cell(p.position))
	for th in w.things:
		var at := w.to_pos(th.cell)
		if p.position.distance_to(at) < Things.REACH and w.building_at.get(th.cell) == here and th.get("storey", 0) == p.storey:
			out.append({kind = "thing", id = th.id, pos = at, title = Things.title_of(th)})


static func stairs_near(w: World, pos: Vector2) -> Vector2i:
	var c := w.to_cell(pos)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var s := c + Vector2i(dx, dy)
			if w.stairs.has(s) and pos.distance_to(w.to_pos(s)) < 13.0:
				return s
	return NONE


## A spot on the street right next to the roof edge, to jump down to.
static func jump_spot(w: World, pos: Vector2) -> Vector2:
	var b: BuildingProp = w.building_at.get(w.to_cell(pos))
	if b and b.data.get("big", false):
		return Vector2.INF  # (far too high: the stairs)
	for d in [Vector2(0, 20), Vector2(0, -20), Vector2(20, 0), Vector2(-20, 0)]:
		var p: Vector2 = pos + d
		if not w.is_roof(w.to_cell(p)) and w.can_stand(p, 5):
			return p
	return Vector2.INF


## A water cell right beside `pos` (the canal's edge), or NONE.
static func water_near(w: World, pos: Vector2) -> Vector2i:
	var c := w.to_cell(pos)
	for d in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var at: Vector2i = c + d
		if w.get_tile(at) == World.WATER and w.to_pos(at).distance_to(pos) < CANAL_REACH:
			return at
	return NONE


static func trap_near(w: World, pos: Vector2) -> int:
	var id := w.door_near(pos, TRAP_REACH)
	return id if id >= 0 and w.is_built(id) and not w.doors[id].broken else -1
