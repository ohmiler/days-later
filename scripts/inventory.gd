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
			return ref[1] in Items.SLOTS or ref[1] in Items.HANDS
		"ground":
			return ref[1] == -1 or (main.pickups.has(ref[1]) and p.position.distance_to(main.pickups[ref[1]].pos) < GROUND_REACH 					and main.pickups[ref[1]].get("storey", 0) == p.storey)
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
	if it != null:
		# Into a fridge it keeps (with power); anywhere else it goes on ageing.
		var box: Dictionary = main.world.container_nodes[ref[1]].data if ref[0] == "box" else {}
		if box.get("kind", "") == "fridge":
			Items.chill_in(it, Buildings.at(main.world, box.cell), main.now())
		else:
			Items.chill_out(it, main.now())
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
				main._spawn_pickup(p.position + Vector2(randf_range(-6, 6), randf_range(2, 7)), it, p.storey)
		"box":
			main.world.container_nodes[ref[1]].items[ref[2]] = it


## Where `it` goes when sent to the bag with no particular slot: onto a stack
## of the same thing with room, else the first empty slot, else -1.
func _inv_slot_for(p: Player, it: Dictionary) -> int:
	return _slot_for(p.inv, it)


func _slot_for(slots: Array, it: Dictionary) -> int:
	if Items.stack(it.id) > 1 and Items.plain(it):
		for i in slots.size():
			var o = slots[i]
			if o != null and o.id == it.id and o.n < Items.stack(it.id) and Items.plain(o):
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
	# Hands take weapons. A two-handed one goes in the right hand, and needs the left free.
	if b[0] == "worn" and b[1] in Items.HANDS:
		if not Items.is_weapon(x.id):
			main._toast(p, "ถือได้แต่อาวุธ")
			return
		if p.worn.get("hands") != null and Items.def(p.worn.hands.id).get("no_grip", false):
			main._toast(p, "ใส่%sอยู่ · กำอาวุธไม่ได้" % Items.display_name(p.worn.hands.id))
			return
		if Items.two_handed(x.id):
			b = ["worn", "hand_r"]
			if p.worn.get("hand_l") != null and a != ["worn", "hand_l"]:
				var free := p.inv.find(null)
				if free < 0:
					main._toast(p, "%sต้องใช้สองมือ · ปล่อยมือซ้ายก่อน" % Items.display_name(x.id))
					return
				p.inv[free] = p.worn.hand_l  # the left hand lets go to take the other end
				p.worn.erase("hand_l")
		elif b[1] == "hand_l" and p.worn.get("hand_r") != null and Items.two_handed(p.worn.hand_r.id):
			main._toast(p, "ถือ%sสองมืออยู่" % Items.display_name(p.worn.hand_r.id))
			return
		if a == b:
			return
	var y = _ref_get(p, b)
	if b == ["worn", "hands"] and Items.def(x.id).get("no_grip", false) and (p.worn.get("hand_r") != null or p.worn.get("hand_l") != null):
		main._toast(p, "วางอาวุธในมือก่อน · ใส่%sแล้วกำอะไรไม่ได้" % Items.display_name(x.id))
		return
	# Only clothes go on the body, and only in their own place.
	if b[0] == "worn" and b[1] not in Items.HANDS and (not Items.is_wear(x.id) or Items.def(x.id).slot != b[1]):
		main._toast(p, "ใส่ตรงนั้นไม่ได้")
		return
	var fits_back: bool = y == null or (Items.is_weapon(y.id) if a[1] in Items.HANDS else (Items.is_wear(y.id) and Items.def(y.id).slot == a[1])) \
			if a[0] == "worn" else true
	if a[0] == "worn" and y != null and b[0] != "ground" and not fits_back:
		b = ["inv", p.inv.find(null)]  # taking clothes off onto a full slot: find an empty one instead
		if b[1] < 0:
			main._toast(p, "กระเป๋าเต็ม")
			return
		y = null
	if b[0] == "ground":
		_ref_set(p, a, null)
		_ref_set(p, ["ground", -1], x)
	elif y != null and y.id == x.id and Items.stack(x.id) > 1 and Items.plain(x) and Items.plain(y):
		var room: int = Items.stack(x.id) - y.n
		var n := mini(room, x.n)
		y.n += n
		x.n -= n
		if x.n <= 0:
			_ref_set(p, a, null)
		elif a[0] == "ground":
			main.pickup_del.rpc(a[1])  # the rest stays on the ground as a fresh pile
			main._spawn_pickup(p.position + Vector2(randf_range(-6, 6), 4), x, p.storey)
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
			main._spawn_pickup(p.position + Vector2(randf_range(-6, 6), 5), it, p.storey)
			main._toast(p, "%s ตกพื้น · กระเป๋าไม่พอ" % Items.display_name(it.id))
	p.inv.resize(n)
	p.sel = mini(p.sel, Items.INV_SIZE - 1)


## Put an item in the first slot that takes it. Returns false if full.
func _give(p: Player, id: String) -> bool:
	var d := Items.def(id)
	if d.get("type") != "weapon":
		for it in p.inv:
			if it != null and it.id == id and it.n < Items.stack(id) and Items.plain(it):
				it.n += 1
				return true
	for i in p.inv.size():
		if p.inv[i] == null:
			p.inv[i] = Items.make(id)
			return true
	return false


## Everything a dead player had falls to the ground. When they `turned`, their
## clothes stay on the zombie they became instead (and drop when it dies).
func _drop_everything(p: Player, turned := false) -> void:
	var k := 0
	for slot in p.worn:
		if not turned:
			main._spawn_pickup(p.position + Vector2.from_angle(k * 1.7 + 0.5) * 9, p.worn[slot], p.storey)
		k += 1
	p.worn.clear()  # still drawn on the body until respawn (see Player.refresh_wear)
	for i in p.inv.size():
		if p.inv[i] != null:
			main._spawn_pickup(p.position + Vector2.from_angle(i * TAU / 8) * 6, p.inv[i], p.storey)
			p.inv[i] = null
	_send_inv(p)


@rpc("any_peer", "call_remote", "reliable")
func req_select(slot: int) -> void:
	var p := main._sender()
	if p and slot >= 0 and slot < mini(p.inv.size(), Items.INV_SIZE):
		p.sel = slot
		# Picking a weapon on the hotbar takes it in the right hand (what was there goes in its place).
		if p.inv[slot] != null and Items.is_weapon(p.inv[slot].id):
			_move_as(p, ["inv", slot], ["worn", "hand_r"])
			return
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
	if it != null and Items.def(it.id).get("blow", false):
		blow(p)
		return
	if it != null and Items.is_wear(it.id):
		_equip(p, p.sel)
		return
	if it != null and Items.is_weapon(it.id):
		_move_as(p, ["inv", p.sel], ["worn", "hand_r"])  # "use" a weapon: hold it
		return
	if it != null and Items.def(it.id).get("type") == "trap":
		main.doors._place_trap(p, it)
		return
	if it != null and Items.holds(it.id) > 0:
		drink_from(p, it)
		return
	if it == null or Items.def(it.id).get("type") != "use":
		return
	var d := Items.def(it.id)
	if d.has("cooks") and d.get("food", 0.0) <= 0.0:
		main._toast(p, "ต้องหุงก่อน · ใส่หม้อกับน้ำแล้วตั้งบนเตาในครัว")
		return
	if d.has("condition"):
		main._toast(p, Body.add_condition(p, d.condition, main.now()))
	if d.get("splint", false) and not Body.splint(p):
		main._toast(p, "ไม่มีข้อเท้าแพลงให้ใส่เฝือก")
		return
	if d.get("splint", false):
		main.skills.gain(p, "medic", "splint")
	var off := Items.spoiled(it, main.now())
	p.hp = minf(Player.MAX_HP, p.hp + d.get("heal", 0.0) * Skills.mult(p, "heal"))
	var cooked: bool = it.has("made") and Items.cooked_ids().has(it.id)  # (a good cook's rice fills you more)
	p.hunger = clampf(p.hunger + d.get("food", 0.0) * (0.5 if off else 1.0) * (Skills.mult(p, "cooked_food") if cooked else 1.0), 0.0, 100.0)
	if off and randf() < SPOILED_SICK:
		main._toast(p, Body.add_condition(p, "food_poisoning", main.now()))
	p.thirst = clampf(p.thirst + d.get("drink", 0.0), 0.0, 100.0)
	p.stamina = minf(100.0, p.stamina + d.get("stamina", 0.0))
	if d.get("food", 0.0) > 0.0:
		main.quests.note(p, "eat", {item = it.id})
	if d.get("drink", 0.0) > 0.0:
		main.quests.note(p, "drink", {item = it.id})
	if d.get("cure", 0.0) > 0.0 and Body.clear_fever(p):
		main._toast(p, "แผลหายอักเสบแล้ว")
		main.skills.gain(p, "medic", "cure")
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
			main.skills.gain(p, "medic", "treat", done)
			main.quests.note(p, "treat", {}, done)
	it.n -= 1
	if it.n <= 0:
		p.inv[p.sel] = null
	if d.has("leaves"):
		_give(p, d.leaves)  # (the empty bottle; if the bag is full, it's just gone)
	main.fx_sound.rpc("eat", p.position)
	main._toast(p, "ใช้ %s" % Items.display_name(it.id))
	_send_inv(p)


## One sip from a bottle or a pot: what water it was decides how much it
## helps and whether it makes you ill (Items.LIQUIDS).
const SPOILED_SICK := 0.7  # eating something gone off: this likely to make you ill


func drink_from(p: Player, it: Dictionary) -> void:
	var f := Items.fill_of(it)
	if f.is_empty():
		main._toast(p, "%s ว่างเปล่า · เติมน้ำที่ก๊อก หรือตักน้ำคลอง" % Items.display_name(it.id))
		return
	var liq: Dictionary = Items.LIQUIDS.get(f.what, Items.LIQUIDS.clean)
	p.thirst = clampf(p.thirst + liq.drink, 0.0, 100.0)
	f.n -= 1
	if f.n <= 0:
		it.erase("fill")
	main.fx_sound.rpc("eat", p.position)
	if randf() < liq.sick:
		main._toast(p, Body.add_condition(p, "diarrhea", main.now()))
	else:
		main._toast(p, "ดื่ม%s" % liq.name + ("" if liq.sick == 0.0 else " · เสี่ยงท้องเสีย ต้มก่อนดีกว่า"))
	_send_inv(p)


## Pour `what` water into the containers `p` carries that have room for it
## (the same water or empty), up to `sips`. Returns how many sips went in.
func fill_containers(p: Player, what: String, sips: int) -> int:
	var poured := 0
	for it in p.inv:
		if sips <= 0:
			break
		if it == null or Items.holds(it.id) <= 0:
			continue
		var f := Items.fill_of(it)
		if not f.is_empty() and f.what != what:
			continue
		var n: int = f.get("n", 0)
		var add := mini(Items.holds(it.id) - n, sips)
		if add > 0:
			it.fill = {what = what, n = n + add}
			sips -= add
			poured += add
	if poured > 0:
		_send_inv(p)
	return poured


## `p` bandages `q`'s worst open wound (first aid's treat_other), with a
## bandage from `p`'s bag.
func treat_other(p: Player, q: Player) -> void:
	if q == null or not q.alive() or not Skills.has(p, "treat_other"):
		return
	var slot := -1
	for id in ["bandage", "firstaid"]:
		for k in p.inv.size():
			if slot < 0 and p.inv[k] != null and p.inv[k].id == id:
				slot = k
	if slot < 0:
		return
	if not Body.bandage(q, -1, p):
		main._toast(p, "%s ไม่มีแผลที่ต้องพัน" % q.pname)
		return
	p.inv[slot].n -= 1
	if p.inv[slot].n <= 0:
		p.inv[slot] = null
	q.bleeding = q.wounds.any(func(w): return w.bleeding and not w.bandaged)
	_send_inv(p)
	main.skills.gain(p, "medic", "treat", 2.0)  # (looking after someone else teaches more)
	main.fx_sound.rpc("rustle", q.position)
	main._toast(p, "พันแผลให้ %s แล้ว" % q.pname)
	main._toast(q, "%s พันแผลให้คุณ" % p.pname)


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
	main._spawn_pickup(p.position + p.aim.normalized() * 8, p.inv[p.sel], p.storey)
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
	main.quests.note(p, "search")
	# What turned up stays in the furniture: the bag screen opens on it and you
	# take what you want. Anything left behind is still there later.
	var bid := Buildings.at(main.world, f.data.cell)
	var bkind: String = main.world.buildings[bid].kind if bid >= 0 else ""
	var place := Items.place_in(f.data.table, bkind)
	var found := Items.roll(place, f.data.kind, _loot_rng, Items.tier_of(f.data.table, bkind))
	f.items.resize(FurnitureProp.SIZE)
	for id in found:
		var it := Items.make(id, _loot_rng)
		if Items.def(id).get("spoil", 0.0) > 0.0:
			# (left on the stall since it all began: part way to going off already)
			it.made = main.now() - _loot_rng.randf() * Items.def(id).spoil * 0.5 * Main.HOUR
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
func search_started(duration: float, what := "", recipe := "") -> void:
	main.search_total = maxf(duration, 0.01)
	main.search_until = Time.get_ticks_msec() / 1000.0 + duration
	main.search_what = what
	main.search_recipe = recipe


@rpc("authority", "call_local", "reliable")
func container_searched(id: int) -> void:
	main.world.container_nodes[id].set_searched(true)
	var me: Player = main.players.get(multiplayer.get_unique_id())
	if me and me.position.distance_to(main.world.container_nodes[id].position) < 30:
		main.ui.tutorial("search")


var _blow_cd := {}  # peer -> when (real seconds) they can blow again


## Blow a whistle (in the bag or round your neck): every zombie around hears
## it and comes to look. A friend can pull them off you, or you off a door.
func blow(p: Player) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < float(_blow_cd.get(p.peer_id, 0.0)):
		return
	_blow_cd[p.peer_id] = now + 1.5
	main.fx_sound.rpc("whistle", p.position)
	main._make_noise(p.position, main.survival.WHISTLE_NOISE, p.storey)
	main._toast(p, "เป่านกหวีด · ซอมบี้แถวนี้ได้ยินแล้ว")
