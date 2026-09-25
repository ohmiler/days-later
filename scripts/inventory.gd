class_name Inventory
extends Node
## The bag, clothes and furniture: moving things, using them, searching and storing.
## Split out of main.gd; shared state (world, players, zombies, pickups) lives there.

var main: Main


const SEARCH_TIME := 1.6
func _send_inv(p: Player) -> void:
	p.weapon_id = p.held_weapon()
	main._notify(p.peer_id, &"inv_sync", [p.inv, p.sel, p.worn])


# --- The bag screen: moving things between slots ----------------------------
# A ref names a slot: ["inv", index] (-1 = wherever it fits), ["worn", slot],
# ["ground", pickup id] (-1 = drop at your feet). Later: ["box", container, index].

const GROUND_REACH := 30.0


func _ref_ok(p: Player, ref: Array) -> bool:
	if ref.size() == 3 and ref[0] == "box":
		var cid = ref[1]
		return cid is int and cid == p.open_box and cid >= 0 and cid < main.world.container_nodes.size() \
				and ref[2] is int and ref[2] >= -1 and ref[2] < FurnitureProp.SIZE
	if ref.size() != 2:
		return false
	match ref[0]:
		"inv":
			return ref[1] is int and ref[1] >= -1 and ref[1] < p.inv.size()
		"worn":
			return ref[1] in Items.SLOTS
		"ground":
			return ref[1] == -1 or (main.pickups.has(ref[1]) and p.position.distance_to(main.pickups[ref[1]].pos) < GROUND_REACH)
	return false


func _ref_get(p: Player, ref: Array) -> Variant:
	match ref[0]:
		"inv":
			return p.inv[ref[1]] if ref[1] >= 0 else null
		"worn":
			return p.worn.get(ref[1])
		"ground":
			return main.pickups[ref[1]].item if ref[1] >= 0 else null
		"box":
			return main.world.container_nodes[ref[1]].items[ref[2]] if ref[2] >= 0 else null
	return null


func _ref_set(p: Player, ref: Array, it: Variant) -> void:
	match ref[0]:
		"inv":
			p.inv[ref[1]] = it
		"worn":
			if it == null:
				p.worn.erase(ref[1])
			else:
				p.worn[ref[1]] = it
		"ground":
			if ref[1] >= 0:
				main.pickup_del.rpc(ref[1])
			if it != null:
				main._spawn_pickup(p.position + Vector2(randf_range(-6, 6), randf_range(2, 7)), it)
		"box":
			main.world.container_nodes[ref[1]].items[ref[2]] = it


## Where `it` goes when sent to the bag with no particular slot: onto a stack
## of the same thing with room, else the first empty slot, else -1.
func _inv_slot_for(p: Player, it: Dictionary) -> int:
	return _slot_for(p.inv, it)


func _slot_for(slots: Array, it: Dictionary) -> int:
	if Items.stack(it.id) > 1:
		for i in slots.size():
			var o = slots[i]
			if o != null and o.id == it.id and o.n < Items.stack(it.id):
				return i
	return slots.find(null)


## Show a container's contents in `p`'s bag screen.
func _open_box(p: Player, cid: int) -> void:
	var f: FurnitureProp = main.world.container_nodes[cid]
	if f.items.size() != FurnitureProp.SIZE:
		f.items.resize(FurnitureProp.SIZE)
	p.open_box = cid
	main._notify(p.peer_id, &"box_open", [cid, f.items])


## Everyone looking into this container sees the change.
func _sync_box(cid: int) -> void:
	var f: FurnitureProp = main.world.container_nodes[cid]
	for q: Player in main.players.values():
		if q.open_box == cid:
			main._notify(q.peer_id, &"box_open", [cid, f.items])


@rpc("any_peer", "call_remote", "reliable")
func req_close_box() -> void:
	var p := main._sender()
	if p:
		p.open_box = -1


## Client: a container opened (or closed, with cid -1) in the bag screen.
@rpc("authority", "call_remote", "reliable")
func box_open(cid: int, items: Array) -> void:
	if cid < 0:
		main.ui.close_box()
		return
	main.ui.open_box(cid, items, Interact.container_title(main.world.container_nodes[cid].data.kind))


## Drag and drop, shift-click and "take" all come through here: the server
## checks the move makes sense, then stacks or swaps.
@rpc("any_peer", "call_remote", "reliable")
func req_move(a: Array, b: Array) -> void:
	var p := main._sender()
	if p == null or not p.alive() or not _ref_ok(p, a) or not _ref_ok(p, b) or a == b:
		return
	var x = _ref_get(p, a)
	if x == null:
		return
	if b[0] == "inv" and b[1] == -1:
		b = ["inv", _inv_slot_for(p, x)]
		if b[1] < 0:
			main._toast(p, "กระเป๋าเต็ม")
			return
	if b[0] == "box" and b[2] == -1:
		b = ["box", b[1], _slot_for(main.world.container_nodes[b[1]].items, x)]
		if b[2] < 0:
			main._toast(p, "ตู้เต็ม")
			return
	if b[0] == "ground" and p.on_roof:
		main._toast(p, "วางของบนหลังคาไม่ได้")
		return
	var y = _ref_get(p, b)
	# Only clothes go on the body, and only in their own place.
	if b[0] == "worn" and (not Items.is_wear(x.id) or Items.def(x.id).slot != b[1]):
		main._toast(p, "ใส่ตรงนั้นไม่ได้")
		return
	if a[0] == "worn" and y != null and b[0] != "ground" and (not Items.is_wear(y.id) or Items.def(y.id).slot != a[1]):
		b = ["inv", p.inv.find(null)]  # taking clothes off onto a full slot: find an empty one instead
		if b[1] < 0:
			main._toast(p, "กระเป๋าเต็ม")
			return
		y = null
	if b[0] == "ground":
		_ref_set(p, a, null)
		_ref_set(p, ["ground", -1], x)
	elif y != null and y.id == x.id and Items.stack(x.id) > 1:
		var room: int = Items.stack(x.id) - y.n
		var n := mini(room, x.n)
		y.n += n
		x.n -= n
		if x.n <= 0:
			_ref_set(p, a, null)
		elif a[0] == "ground":
			main.pickup_del.rpc(a[1])  # the rest stays on the ground as a fresh pile
			main._spawn_pickup(p.position + Vector2(randf_range(-6, 6), 4), x)
	else:
		_ref_set(p, a, y if a[0] != "ground" else null)
		if a[0] == "ground" and y != null:
			_ref_set(p, ["ground", -1], y)
		_ref_set(p, b, x)
	if a[0] == "worn" or b[0] == "worn":
		p.refresh_wear()
		_fit_bag(p)
	main.fx_sound.rpc("pickup" if a[0] in ["ground", "box"] else "rustle", p.position)
	_send_inv(p)
	if a[0] == "box" or b[0] == "box":
		_sync_box(a[1] if a[0] == "box" else b[1])


## Right-click "use" in the bag screen: eat, heal, put on, or take off.
@rpc("any_peer", "call_remote", "reliable")
func req_use_ref(ref: Array) -> void:
	var p := main._sender()
	if p == null or not p.alive() or not _ref_ok(p, ref):
		return
	match ref[0]:
		"worn":
			_move_as(p, ref, ["inv", -1])
		"ground":
			_move_as(p, ref, ["inv", -1])
		"inv":
			if ref[1] < 0 or p.inv[ref[1]] == null:
				return
			var keep := p.sel
			p.sel = ref[1]
			_use_selected(p)
			p.sel = keep if keep < Items.INV_SIZE else 0
			_send_inv(p)


## Run a move for `p` from inside another handler (the sender is already known).
func _move_as(p: Player, a: Array, b: Array) -> void:
	var saved := main._acting
	main._acting = p
	req_move(a, b)
	main._acting = saved


@rpc("any_peer", "call_remote", "reliable")
func req_split(ref: Array) -> void:
	var p := main._sender()
	if p == null or not _ref_ok(p, ref) or ref[0] != "inv" or ref[1] < 0:
		return
	var it = p.inv[ref[1]]
	var free := p.inv.find(null)
	if it == null or it.n < 2 or free < 0:
		main._toast(p, "ไม่มีช่องว่างให้แบ่ง" if it != null and it.n >= 2 else "")
		return
	var half: int = it.n / 2
	it.n -= half
	p.inv[free] = {id = it.id, n = half, hp = it.get("hp", 0)}
	_send_inv(p)


## Put on the clothing in hotbar slot `idx`; whatever was worn there goes into
## that hotbar slot in its place.
func _equip(p: Player, idx: int) -> void:
	var it: Dictionary = p.inv[idx]
	var slot: String = Items.def(it.id).slot
	var old = p.worn.get(slot)
	p.worn[slot] = it
	p.inv[idx] = old
	p.refresh_wear()
	_fit_bag(p)
	main.fx_sound.rpc("rustle", p.position)
	main._toast(p, "สวม%s" % Items.display_name(it.id))
	_send_inv(p)


@rpc("any_peer", "call_remote", "reliable")
func req_unequip(slot: String) -> void:
	var p := main._sender()
	if p == null or not p.alive() or p.worn.get(slot) == null:
		return
	var it: Dictionary = p.worn[slot]
	# Taking the bag off loses its slots, so the item must fit in what is left.
	var room: int = p.inv.size() - int(Items.def(it.id).get("bag", 0))
	var free := -1
	for i in room:
		if p.inv[i] == null:
			free = i
			break
	if free < 0:
		main._toast(p, "กระเป๋าเต็ม · วางของก่อน (G)")
		return
	p.inv[free] = it
	p.worn.erase(slot)
	p.refresh_wear()
	_fit_bag(p)
	main.fx_sound.rpc("rustle", p.position)
	main._toast(p, "ถอด%s" % Items.display_name(it.id))
	_send_inv(p)


## Grow or shrink the hotbar to what the worn bag allows. Things in slots that
## go away move into free slots, or fall to the ground if there is no room.
func _fit_bag(p: Player) -> void:
	var n := p.bag_size()
	if p.inv.size() < n:
		p.inv.resize(n)
		return
	for i in range(n, p.inv.size()):
		var it = p.inv[i]
		if it == null:
			continue
		var moved := false
		for j in n:
			if p.inv[j] == null:
				p.inv[j] = it
				moved = true
				break
		if not moved:
			main._spawn_pickup(p.position + Vector2(randf_range(-6, 6), 5), it)
			main._toast(p, "%s ตกพื้น · กระเป๋าไม่พอ" % Items.display_name(it.id))
	p.inv.resize(n)
	p.sel = mini(p.sel, Items.INV_SIZE - 1)


## Put an item in the first slot that takes it. Returns false if full.
func _give(p: Player, id: String) -> bool:
	var d := Items.def(id)
	if d.get("type") != "weapon":
		for it in p.inv:
			if it != null and it.id == id and it.n < Items.stack(id):
				it.n += 1
				return true
	for i in p.inv.size():
		if p.inv[i] == null:
			p.inv[i] = {id = id, n = 1, hp = d.get("hp", 0)}
			return true
	return false


## Everything a dead player had falls to the ground. When they `turned`, their
## clothes stay on the zombie they became instead (and drop when it dies).
func _drop_everything(p: Player, turned := false) -> void:
	var k := 0
	for slot in p.worn:
		if not turned:
			main._spawn_pickup(p.position + Vector2.from_angle(k * 1.7 + 0.5) * 9, p.worn[slot])
		k += 1
	p.worn.clear()  # still drawn on the body until respawn (see Player.refresh_wear)
	for i in p.inv.size():
		if p.inv[i] != null:
			main._spawn_pickup(p.position + Vector2.from_angle(i * TAU / 8) * 6, p.inv[i])
			p.inv[i] = null
	_send_inv(p)


@rpc("any_peer", "call_remote", "reliable")
func req_select(slot: int) -> void:
	var p := main._sender()
	if p and slot >= 0 and slot < mini(p.inv.size(), Items.INV_SIZE):
		p.sel = slot
		_send_inv(p)


@rpc("any_peer", "call_remote", "reliable")
func req_use() -> void:
	var p := main._sender()
	if p and p.alive():
		_use_selected(p)


## Right-click on a hotbar slot: select it and use it in one go.
@rpc("any_peer", "call_remote", "reliable")
func req_use_slot(idx: int) -> void:
	var p := main._sender()
	if p and p.alive() and idx >= 0 and idx < p.inv.size() and p.inv[idx] != null:
		p.sel = idx
		_use_selected(p)
		_send_inv(p)


## Q: patch yourself up with whatever suits best, wherever it is in the bag.
## Bleeding comes first (the smallest thing that stops it), then the smallest
## heal that covers what you have lost, so the big kits are kept for real trouble.
@rpc("any_peer", "call_remote", "reliable")
func req_quick_heal() -> void:
	var p := main._sender()
	if p == null or not p.alive():
		return
	var missing := Player.MAX_HP - p.hp
	var best := -1
	var best_score := INF
	for i in p.inv.size():
		var it = p.inv[i]
		if it == null:
			continue
		var d := Items.def(it.id)
		var heal: float = d.get("heal", 0.0)
		if heal <= 0.0:
			continue
		var score: float
		if p.bleeding:
			if not d.get("stop_bleed", false):
				continue
			score = heal
		elif missing < 1.0:
			continue
		else:
			score = heal - missing if heal >= missing else 1000.0 - heal
		if score < best_score:
			best_score = score
			best = i
	if best < 0:
		main._toast(p, "ไม่มีของห้ามเลือด" if p.bleeding else ("เลือดเต็มแล้ว" if missing < 1.0 else "ไม่มีของรักษาในกระเป๋า"))
		return
	var keep := p.sel
	p.sel = best
	_use_selected(p)
	p.sel = keep
	_send_inv(p)


func _use_selected(p: Player) -> void:
	var it = p.inv[p.sel]
	if it != null and Items.is_wear(it.id):
		_equip(p, p.sel)
		return
	if it != null and Items.def(it.id).get("type") == "trap":
		main.doors._place_trap(p, it)
		return
	if it == null or Items.def(it.id).get("type") != "use":
		return
	var d := Items.def(it.id)
	p.hp = minf(Player.MAX_HP, p.hp + d.get("heal", 0.0))
	p.hunger = clampf(p.hunger + d.get("food", 0.0), 0.0, 100.0)
	p.thirst = clampf(p.thirst + d.get("drink", 0.0), 0.0, 100.0)
	p.stamina = minf(100.0, p.stamina + d.get("stamina", 0.0))
	if d.get("cure", 0.0) > 0.0 and p.infection > 0.0:
		p.infection = maxf(0.0, p.infection - d.cure)
		if p.infection <= 0.0:
			main._toast(p, "หายจากการติดเชื้อแล้ว")
	if d.get("stop_bleed", false):
		# A bandage goes on the worst open wound; a first-aid kit dresses them all.
		var done := 0
		while Body.bandage(p):
			done += 1
			if d.get("heal", 0.0) < 50.0:
				break
		p.bleeding = p.wounds.any(func(w): return w.bleeding and not w.bandaged)
		if done > 0:
			main._toast(p, "พันแผลแล้ว")
	it.n -= 1
	if it.n <= 0:
		p.inv[p.sel] = null
	main.fx_sound.rpc("eat", p.position)
	main._toast(p, "ใช้ %s" % Items.display_name(it.id))
	_send_inv(p)


## Bandage one particular wound (from the body screen), with a bandage from the bag.
@rpc("any_peer", "call_remote", "reliable")
func req_treat(i: int) -> void:
	var p := main._sender()
	if p == null or not p.alive() or i < 0 or i >= p.wounds.size():
		return
	var slot := -1
	for id in ["bandage", "firstaid"]:
		for k in p.inv.size():
			if slot < 0 and p.inv[k] != null and p.inv[k].id == id:
				slot = k
	if slot < 0:
		main._toast(p, "ไม่มีผ้าพันแผล")
		return
	if not Body.bandage(p, i):
		return
	p.inv[slot].n -= 1
	if p.inv[slot].n <= 0:
		p.inv[slot] = null
	p.bleeding = p.wounds.any(func(w): return w.bleeding and not w.bandaged)
	main.fx_sound.rpc("rustle", p.position)
	main._toast(p, "พันแผลที่%sแล้ว" % Body.where(p.wounds[i]))
	_send_inv(p)


@rpc("any_peer", "call_remote", "reliable")
func req_drop() -> void:
	var p := main._sender()
	if p == null or p.inv[p.sel] == null:
		return
	if p.on_roof:
		main._toast(p, "วางของบนหลังคาไม่ได้")
		return
	main._spawn_pickup(p.position + p.aim.normalized() * 8, p.inv[p.sel])
	p.inv[p.sel] = null
	_send_inv(p)


func _tick_search(p: Player, delta: float) -> void:
	if p.search_id < 0:
		return
	var f: FurnitureProp = main.world.container_nodes[p.search_id]
	if not p.alive() or p.move.length() > 0.1 or f.searched or p.position.distance_to(f.position) > main.INTERACT_RANGE + 4:
		p.search_id = -1
		main._notify(p.peer_id, &"search_started", [0.0])
		return
	p.search_t -= delta
	if p.search_t > 0:
		return
	p.search_id = -1
	container_searched.rpc(f.data.id)
	# What turned up stays in the furniture: the bag screen opens on it and you
	# take what you want. Anything left behind is still there later.
	var found := Items.roll(f.data.table, f.data.kind, _loot_rng)
	f.items.resize(FurnitureProp.SIZE)
	for id in found:
		var it := {id = id, n = 1, hp = Items.def(id).get("hp", 0)}
		var slot := _slot_for(f.items, it)
		if slot >= 0:
			if f.items[slot] == null:
				f.items[slot] = it
			else:
				f.items[slot].n += 1
	if found.is_empty():
		main._toast(p, "ไม่มีอะไรเหลือแล้ว · ใช้เก็บของได้")
	else:
		main.fx_sound.rpc("pickup", p.position)
	_open_box(p, f.data.id)


var _loot_rng := RandomNumberGenerator.new()


@rpc("authority", "call_remote", "reliable")
func inv_sync(inv: Array, sel: int, worn: Dictionary) -> void:
	var me: Player = main.players.get(multiplayer.get_unique_id())
	if me:
		me.inv = inv
		me.sel = sel
		me.worn = worn
		me.weapon_id = me.held_weapon()
		if me.weapon_id != "":
			main.ui.tutorial("equip")
	main.ui.set_inventory(inv, sel)
	main.ui.set_worn(worn)


@rpc("authority", "call_remote", "reliable")
func search_started(duration: float) -> void:
	main.search_total = maxf(duration, 0.01)
	main.search_until = Time.get_ticks_msec() / 1000.0 + duration


@rpc("authority", "call_local", "reliable")
func container_searched(id: int) -> void:
	main.world.container_nodes[id].set_searched(true)
	var me: Player = main.players.get(multiplayer.get_unique_id())
	if me and me.position.distance_to(main.world.container_nodes[id].position) < 30:
		main.ui.tutorial("search")
