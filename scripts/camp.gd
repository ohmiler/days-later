class_name Camp
extends Node
## The refugee camp: the grounds of a zone's temple, inside its wall
## (World.camps, from a zone block `use = "temple"`). Where newcomers start
## and survivors without a bed of their own wake up again. Safe: zombies
## never come up in or near it, don't go after anyone inside, can't get
## through the gates, and the soldiers on the gates shoot any that come close.
## The volunteer by the gate starts newcomers off (the first quest, talk,
## gives the starter kit); the notice board hands out the day's jobs.

static var safe_on := true  # (tests turn it off: most of them start at the spawn, which is in the camp; test_camp turns it on)
const CLEAR := 12  # cells round a camp no zombie comes up in (Survival._spawn_zombie)
const GUARD_REACH := 5  # cells outside the wall the soldiers on the gates shoot
const GUARD_EVERY := 1.4  # seconds between shots
## What the volunteer says, a line at a time, once you've had your things.
const TALK := [
	"ในกำแพงวัดปลอดภัย ซอมบี้เข้ามาไม่ได้ ทหารเฝ้าประตูอยู่ทั้งสี่ด้าน",
	"ไม่มีเตียงของตัวเอง ตายแล้วจะฟื้นที่นี่ หาบ้านแล้วนอนเตียงนั้นจะได้ฟื้นที่บ้าน",
	"งานประจำวันดูได้ที่บอร์ดข้าง ๆ ทำแล้วได้ของ ได้ฝีมือ",
	"ของดี ๆ อยู่ในโรงพยาบาลกับห้าง แต่ข้างในยังมีพวกมันติดอยู่ ไปเป็นกลุ่มดีกว่า",
	"ได้ข่าวว่าโรงพยาบาลใหญ่มีทหารที่ติดเชื้อยังใส่เกราะอยู่ ตีตัวไม่เข้า ต้องเล็งหัว",
	"กลางคืนพวกมันมองไม่ค่อยเห็น แต่ได้ยินชัด เดินเงียบ ๆ ไว้",
]

var main: Main
var _t := 0.0
var _talk_i := {}  # peer -> the next line the volunteer says


## Server: the soldiers on the gates shoot the nearest zombie that comes close.
func server_tick(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = GUARD_EVERY
	if not safe_on:
		return
	for camp in main.world.camps:
		var r: Rect2i = camp.rect
		var near: Rect2i = r.grow(GUARD_REACH)
		var best: Zombie = null
		var best_d := INF
		for z: Zombie in main.zombies.values():
			if z.storey != 0 or z.hp <= 0 or not near.has_point(main.world.to_cell(z.position)):
				continue
			var d := _gate(r, z.position).distance_to(z.position)
			if d < best_d:
				best = z
				best_d = d
		if best:
			var from := _gate(r, best.position)
			main.combat.fx_shots.rpc(from, [best.position + Vector2(0, -20)], "pistol")
			main.combat._kill_zombie(best, 1.0 if best.position.x >= from.x else -1.0, "gun", "head")


## The gate nearest `pos`, where the soldier stands (world position).
func _gate(r: Rect2i, pos: Vector2) -> Vector2:
	var c := r.get_center()
	var best := Vector2.ZERO
	for g in [Vector2i(c.x, r.position.y), Vector2i(c.x, r.end.y - 1), Vector2i(r.position.x, c.y), Vector2i(r.end.x - 1, c.y)]:
		var at: Vector2 = main.world.to_pos(g)
		if best == Vector2.ZERO or at.distance_to(pos) < best.distance_to(pos):
			best = at
	return best


## Server: `p` talks to the volunteer: newcomers get their things (the first
## quest's reward); after that, a word of advice.
func talk(p: Player) -> void:
	var was_new: bool = p.quests.get("active", {}).has("intro_camp")
	main.quests.note(p, "talk", {kind = "volunteer"})
	if was_new:
		main._toast(p, "อาสา: รับไปนะ น้ำกับผ้าพันแผล · ข้างนอกหาอาวุธกับของกินเอาเอง แล้วกลับมาที่นี่ได้ทุกเมื่อ")
		return
	var i: int = _talk_i.get(p.peer_id, 0)
	_talk_i[p.peer_id] = i + 1
	main._toast(p, "อาสา: " + TALK[i % TALK.size()])


## Server: `p` reads the notice board: today's jobs, if they haven't had them.
func jobs(p: Player) -> void:
	match main.quests.hand_out_daily(p):
		"new":
			main._toast(p, "รับงานประจำวันแล้ว · ดูมุมขวาบนของจอ")
		"had":
			main._toast(p, "งานของวันนี้รับไปแล้ว · พรุ่งนี้มีงานใหม่")
		"start":
			main._toast(p, "ทำภารกิจเริ่มต้นให้จบก่อน แล้วค่อยมารับงานประจำวัน")


## The camps on the city map: [cell, name].
func map_marks() -> Array:
	return main.world.camps.map(func(c): return [c.rect.get_center(), c.name])
