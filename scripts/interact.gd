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
	if p.on_roof:
		# Up top only the stairs and the roof edge are in reach.
		if Interact.jump_spot(w, p.position) != Vector2.INF:
			out.append({kind = "edge", id = 0, pos = p.position + Vector2(0, 1), title = "ขอบหลังคา"})
		return out
	for pid in main.pickups:
		var pos: Vector2 = main.pickups[pid].pos
		if p.position.distance_to(pos) < PICKUP_REACH:
			out.append({kind = "pickup", id = pid, pos = pos, title = Items.display_name(main.pickups[pid].item.id)})
	# A zombie knocked flat right at your feet: finish it.
	for z: Zombie in main.zombies.values():
		if z.flags & 2 and p.position.distance_to(z.position) < STOMP_REACH:
			out.append({kind = "zombie", id = z.zid, pos = z.position, title = "ซอมบี้ล้มอยู่"})
	var trap := trap_near(w, p.position)
	if trap >= 0:
		out.append({kind = "trap", id = trap, pos = w.to_pos(w.doors[trap].cell), title = World.BUILDS[w.doors[trap].kind].name})
	var door := w.door_near(p.position, 16.0)
	if door >= 0 and not w.is_built(door):
		var d: Dictionary = w.doors[door]
		var win := w.is_window(door)
		var title := "ประตู"
		if win:
			title = "หน้าต่างแตก · ปีนผ่านได้" if not d.closed else "หน้าต่าง"
		elif d.broken:
			title = "ประตูพัง"
		out.append({kind = "window" if win else "door", id = door, pos = w.to_pos(d.cell), title = title})
	var here: BuildingProp = w.building_at.get(w.to_cell(p.position))
	for th in w.things:
		var at := w.to_pos(th.cell)
		if p.position.distance_to(at) < Things.REACH and w.building_at.get(th.cell) == here:
			out.append({kind = "thing", id = th.id, pos = at, title = Things.title_of(th)})
	for f: FurnitureProp in w.container_nodes:
		# Furniture in the same building as you: no reaching through walls.
		if p.position.distance_to(f.position) < CONTAINER_REACH and w.building_at.get(f.data.cell) == here:
			out.append({kind = "container", id = f.data.id, pos = f.position, title = container_title(f.data.kind)})
	return out


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
			out.append(_act("down", "ลงบันได") if p.on_roof else _act("up", "ขึ้นดาดฟ้า"))
		"edge":
			out.append(_act("jump", "กระโดดลง (เจ็บ · เสียงดัง)"))
		"pickup":
			var item: Dictionary = main.pickups[t.id].item
			out.append(_act("take", "เก็บ " + Items.display_name(item.id)))
		"trap":
			out.append(_act("take_trap", "เก็บ" + t.title + "คืน"))
		"door":
			var d: Dictionary = w.doors[t.id]
			if d.broken:
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
			if w.container_nodes[t.id].data.kind == "bed":
				var why: String = main.survival.can_sleep(p)
				out.append(_act("sleep", "นอนพัก", why == "", why))
				if p.bed == t.id:
					out.append(_act("claim", "เตียงประจำของคุณ", false, "ตื่นที่นี่เมื่อตายอยู่แล้ว"))
				else:
					out.append(_act("claim", "ตั้งเป็นเตียงประจำ (ตายแล้วตื่นที่นี่)"))
		"zombie":
			out.append(_act("stomp", "เหยียบหัวให้ตาย"))
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


static func has_wood(p: Player) -> bool:
	return p.inv.any(func(it): return it != null and it.id == "wood")


static func container_title(kind: String) -> String:
	return {shelf = "ชั้นวางของ", fridge = "ตู้เย็น", counter = "เคาน์เตอร์", cabinet = "ตู้",
			table = "โต๊ะ", crate = "ลัง", bed = "เตียง"}.get(kind, "ของ")


# --- Finding things in reach ---------------------------------------------------

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
	for d in [Vector2(0, 20), Vector2(0, -20), Vector2(20, 0), Vector2(-20, 0)]:
		var p: Vector2 = pos + d
		if not w.is_roof(w.to_cell(p)) and w.can_stand(p, 5):
			return p
	return Vector2.INF


static func trap_near(w: World, pos: Vector2) -> int:
	var id := w.door_near(pos, TRAP_REACH)
	return id if id >= 0 and w.is_built(id) and not w.doors[id].broken else -1


static func container_near(w: World, pos: Vector2) -> FurnitureProp:
	var best: FurnitureProp = null
	var best_d := CONTAINER_REACH
	for f: FurnitureProp in w.container_nodes:
		var d := pos.distance_to(f.position)
		if d < best_d:
			best_d = d
			best = f
	return best
