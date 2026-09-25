class_name Body
## Wounds and how you are: what the body screen and the status icons show.
##
## A wound sits on a part of the body until it heals: a bite (bleeds, can go
## bad), a scratch (from smashed glass), a sprained ankle (from a jump: no
## running), a bruise (a bite your clothes stopped). Bandages go on one wound
## at a time; an open bite or scratch can still get infected long after the
## bite itself. Everything heals with time, faster asleep.
##
## Player.wounds: [{kind, part, side, bleeding, bandaged, t}] (server; the
## owner gets a copy through body_sync).

const KINDS := {
	bite = {name = "รอยกัด", heal = 360.0, bare = 0.0, risk = 0.06},  # an open bite doesn't close by itself
	scratch = {name = "แผลถลอก", heal = 180.0, bare = 120.0, risk = 0.02},
	sprain = {name = "ข้อเท้าแพลง", heal = 240.0, bare = 240.0, risk = 0.0},
	bruise = {name = "ฟกช้ำ", heal = 120.0, bare = 120.0, risk = 0.0},
}
## Heal time is in seconds of game (a day is Main.DAY_LENGTH); a bandage
## heals `heal`, bare skin `bare` (0: not at all). Asleep, three times as fast.
const SLEEP_HEAL := 3.0
const RISK_EVERY := 20.0  # seconds between an open wound's chances (`risk`) of going bad
const SIDED := ["arms", "hands", "legs"]

## Infection stages: [from %, name, what it does].
const STAGES := [[0.0, "แผลอักเสบ", "ยังไม่มีอาการ"], [25.0, "มีไข้", "เริ่มอ่อนแรง"],
		[60.0, "ไข้สูง", "เดินช้าลง ตัวร้อน"], [85.0, "ใกล้กลายร่าง", "ต้องใช้ยาปฏิชีวนะด่วน"]]


static func where(w: Dictionary) -> String:
	var name: String = Items.PART_NAMES.get(w.part, w.part)
	if w.part in SIDED:
		name += "ซ้าย" if w.side < 0 else "ขวา"
	return name


static func title(w: Dictionary) -> String:
	return "%s · %s" % [KINDS[w.kind].name, where(w)]


static func infection_stage(inf: float) -> int:
	var s := 0
	for i in STAGES.size():
		if inf >= STAGES[i][0]:
			s = i
	return s


# --- Server ------------------------------------------------------------------------

static func add(p: Player, kind: String, part: String, bleeding := false) -> Dictionary:
	var w := {kind = kind, part = part, side = -1 if randf() < 0.5 else 1, bleeding = bleeding, bandaged = false, t = 0.0}
	p.wounds.append(w)
	p.body_dirty = true
	return w


## The wound a bandage should go on first: bleeding, then bites, then scratches.
static func worst_open(p: Player) -> int:
	var best := -1
	var best_score := 0
	for i in p.wounds.size():
		var w: Dictionary = p.wounds[i]
		if w.bandaged or w.kind in ["sprain", "bruise"]:
			continue
		var score := (4 if w.bleeding else 0) + (2 if w.kind == "bite" else 1)
		if score > best_score:
			best_score = score
			best = i
	return best


## Put a bandage on wound `i` (or the worst open one with -1). Returns whether it went on.
static func bandage(p: Player, i := -1) -> bool:
	if i < 0:
		i = worst_open(p)
	if i < 0 or i >= p.wounds.size() or p.wounds[i].bandaged or p.wounds[i].kind in ["sprain", "bruise"]:
		return false
	p.wounds[i].bandaged = true
	p.wounds[i].bleeding = false
	p.body_dirty = true
	return true


## Heal, bleed and fester, each second of play. Returns a message for the
## player when a wound turns bad or closes, or "".
static func tick(p: Player, delta: float) -> String:
	var msg := ""
	var speed := SLEEP_HEAL if p.sleeping else 1.0
	for w in p.wounds.duplicate():
		var k: Dictionary = KINDS[w.kind]
		var need: float = k.heal if w.bandaged else k.bare
		if need > 0.0:
			w.t += delta * speed
			if w.t >= need:
				p.wounds.erase(w)
				p.body_dirty = true
				if w.kind in ["bite", "sprain"]:
					msg = "%s หายแล้ว" % title(w)
				continue
		# An open wound can go bad while it stays open.
		if not w.bandaged and k.risk > 0.0 and p.infection <= 0.0:
			w["risk_t"] = w.get("risk_t", 0.0) + delta
			if w.risk_t >= RISK_EVERY:
				w.risk_t = 0.0
				if randf() < k.risk:
					p.infection = 12.0
					msg = "%sอักเสบ ติดเชื้อแล้ว · หายาปฏิชีวนะ" % where(w)
	p.bleeding = p.wounds.any(func(w): return w.bleeding and not w.bandaged)
	return msg


static func sprained(wounds: Array) -> bool:
	return wounds.any(func(w): return w.kind == "sprain")


# --- What to show ---------------------------------------------------------------------

## Status icons for the HUD: [{icon, level (0 note, 1 watch out, 2 danger), text}].
static func statuses(p: Player) -> Array:
	var out := []
	for w in p.wounds:
		if w.bandaged:
			continue
		match w.kind:
			"bite":
				out.append({icon = "bite", level = 2, text = "%s · ยังไม่พันแผล · เสี่ยงติดเชื้อ" % title(w)})
			"scratch":
				out.append({icon = "scratch", level = 1, text = "%s · ยังไม่พันแผล" % title(w)})
			"sprain":
				out.append({icon = "sprain", level = 1, text = "%s · วิ่งไม่ได้ เดินช้าลง" % title(w)})
	if p.bleeding:
		out.append({icon = "bleed", level = 2, text = "เลือดออก · พันแผลด่วน"})
	if p.infection > 0.0:
		var s: Array = STAGES[infection_stage(p.infection)]
		out.append({icon = "fever", level = 2 if p.infection >= 60.0 else 1, text = "ติดเชื้อ · %s · %s" % [s[1], s[2]]})
	if p.thirst < 25.0:
		out.append({icon = "thirst", level = 2 if p.thirst <= 0.0 else 1, text = "ขาดน้ำ" if p.thirst <= 0.0 else "กระหายน้ำ"})
	if p.hunger < 25.0:
		out.append({icon = "hunger", level = 2 if p.hunger <= 0.0 else 1, text = "อดอาหาร" if p.hunger <= 0.0 else "หิว"})
	if p.exhausted:
		out.append({icon = "tired", level = 1, text = "หมดแรง · พักก่อนวิ่ง"})
	if p.load_speed() < 1.0:
		out.append({icon = "heavy", level = 1, text = "แบกหนักเกิน · เดินช้าลง"})
	if p.heat() >= 0.4:
		out.append({icon = "heat", level = 0, text = "ใส่ของหนา · ร้อน กระหายน้ำเร็ว"})
	return out


## Where a wound shows on the doll (front view, the rig's space).
static func marker(w: Dictionary, view: int) -> Vector2:
	var s: float = w.side
	var at: Vector2 = {head = Vector2(0, -26), face = Vector2(0, -23), neck = Vector2(0, -20.4), torso = Vector2(0, -15),
			arms = Vector2(5.0 * s, -14.5), hands = Vector2(5.0 * s, -11), legs = Vector2(1.6 * s, -4.5)}.get(w.part, Vector2(0, -15))
	match view:
		Look.FRONT:
			at.x = -at.x  # facing us, their left is on our right
		Look.SIDE:
			at.x *= 0.15
	return at


## Little icons, drawn in code (for the HUD and the body list).
static func draw_icon(ci: CanvasItem, c: Vector2, kind: String, col: Color, s := 1.0) -> void:
	match kind:
		"bite":  # two arcs of teeth marks
			for sy in [-1.0, 1.0]:
				for i in 4:
					ci.draw_circle(c + Vector2((-4.5 + i * 3.0) * s, sy * (2.6 - absf(i - 1.5) * 0.6) * s), 0.9 * s, col)
		"scratch":
			for i in 3:
				ci.draw_line(c + Vector2((-5 + i * 3) * s, -5 * s), c + Vector2((-2 + i * 3) * s, 5 * s), col, 1.4 * s)
		"bleed":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7) * s, c + Vector2(4, 1) * s, c + Vector2(-4, 1) * s]), col)
			ci.draw_circle(c + Vector2(0, 1.5) * s, 4 * s, col)
		"fever":  # a thermometer
			ci.draw_rect(Rect2(c + Vector2(-1.5, -7) * s, Vector2(3, 10) * s), col)
			ci.draw_circle(c + Vector2(0, 4) * s, 3 * s, col)
		"thirst":  # a glass
			ci.draw_polyline(PackedVector2Array([c + Vector2(-4, -6) * s, c + Vector2(-3, 6) * s, c + Vector2(3, 6) * s, c + Vector2(4, -6) * s]), col, 1.5 * s)
			ci.draw_rect(Rect2(c + Vector2(-3, 1) * s, Vector2(6, 4) * s), col)
		"hunger":  # a bowl
			ci.draw_arc(c + Vector2(0, -1) * s, 6 * s, 0, PI, 10, col, 2.0 * s)
			ci.draw_line(c + Vector2(-7, -1) * s, c + Vector2(7, -1) * s, col, 1.5 * s)
		"tired":  # a run-down bolt
			ci.draw_polyline(PackedVector2Array([c + Vector2(2, -7) * s, c + Vector2(-3, 1) * s, c + Vector2(2, 0) * s, c + Vector2(-2, 7) * s]), col, 1.6 * s)
		"heavy":  # a weight
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-4, -2) * s, c + Vector2(4, -2) * s, c + Vector2(6, 6) * s, c + Vector2(-6, 6) * s]), col)
			ci.draw_arc(c + Vector2(0, -3) * s, 2.5 * s, PI, TAU, 6, col, 1.4 * s)
		"heat":  # a sun
			ci.draw_circle(c, 3.2 * s, col)
			for i in 8:
				var d := Vector2.from_angle(i * TAU / 8)
				ci.draw_line(c + d * 4.6 * s, c + d * 7 * s, col, 1.2 * s)
		"sprain":  # a bent leg
			ci.draw_polyline(PackedVector2Array([c + Vector2(-2, -7) * s, c + Vector2(1, 0) * s, c + Vector2(-1, 6) * s, c + Vector2(5, 6) * s]), col, 2.0 * s)
			ci.draw_line(c + Vector2(3, -2) * s, c + Vector2(6, -4) * s, col, 1.2 * s)
		"bruise":
			ci.draw_circle(c, 5 * s, Color(col, 0.6))
			ci.draw_circle(c, 2.5 * s, col)
		"bandaged":  # a strip with a cross
			ci.draw_rect(Rect2(c + Vector2(-7, -3) * s, Vector2(14, 6) * s), col)
			ci.draw_line(c + Vector2(-1.5, 0) * s, c + Vector2(1.5, 0) * s, Color(0, 0, 0, 0.4), 1.0 * s)
			ci.draw_line(c + Vector2(0, -1.5) * s, c + Vector2(0, 1.5) * s, Color(0, 0, 0, 0.4), 1.0 * s)
		_:
			ci.draw_circle(c, 4 * s, col)


const LEVEL_COLORS := [Color("b8b0a0"), Color("f2c230"), Color("ff5a4a")]
