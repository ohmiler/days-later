extends SceneTree
## The clothes lookbook: every outfit below in every pose and view the game
## draws, on one sheet, to look over after adding a pose or a garment. Not a
## pass/fail test (tests/test_clothes.gd checks every template has every
## view); run it windowed and open the picture:
##
##   godot --path . -s res://tests/lookbook.gd -- --out=C:/somewhere/lookbook.png
##
## (No --out: user://lookbook.png.) Between them the outfits wear every
## garment in data/items.cfg; add a row when a new kind of thing comes along.

const OUTFITS := [
	{},
	{head = "cap", body = "hoodie", legs = "jeans", feet = "sneakers", back = "schoolbag", face = "sunglasses"},
	{head = "fullface", body = "bikerjacket", over = "rider", hands = "leathergloves", feet = "boots", knees = "kneepads"},
	{head = "helmet", over = "stabvest", back = "backpack", hands = "gloves", arms = "armguards", face = "mask", knees = "shinguards"},
	{over = "raincoat", legs = "shorts", strap = "satchel", neck = "scarf", feet = "boots"},
	{body = "jacket", over = "magarmor", hands = "chaingloves", head = "cap", back = "backpack"},
	{over = "vest", legs = "jeans", feet = "boots", head = "helmet", strap = "satchel"},
]
const CELL := Vector2(44, 46)
const ZOOM := 3.0


class Fig extends Node2D:
	var lk := {}
	var st := {}
	var top := {}

	func _draw() -> void:
		draw_line(Vector2(-16, 0), Vector2(16, 0), Color(0, 0, 0, 0.18), 0.5)
		if top.is_empty():
			Look.draw(self, st, lk)
		else:
			TopRig.draw(self, top, lk)


## Every pose as [label, st] for the rig, or [label, {}, top] for TopRig.
static func poses() -> Array:
	var leap: Array = Player.leap_keys(true)
	return [
		["front", {view = [Look.FRONT, false]}],
		["side", {view = [Look.SIDE, false], moving = true, phase = 1.2}],
		["back", {view = [Look.BACK, false]}],
		["run", {view = [Look.SIDE, false], moving = true, phase = 1.6, run = 1.0}],
		["punch", {view = [Look.SIDE, false], attack = Look.PUNCH_R, ext = 0.8, guard = true}],
		["kick", {view = [Look.FRONT, false], attack = Look.KICK, ext = 0.6}],
		["leap", {view = [Look.SIDE, false], anchors = leap[1], lean = leap[1].lean}],
		["crawl", {view = [Look.SIDE, false], anchors = Player.crawl_anchors(0.7), lean = Player.CRAWL_LEAN}],
		["fallen", {view = [Look.SIDE, false], fall = 1.0, fall_dir = 1.0}],
		["crawl up", {}, TopRig.prone(false, 0.7)],
		["crawl dn", {}, TopRig.prone(true, 0.7)],
		["asleep", {}, TopRig.supine(true)],
		["asleep dn", {}, TopRig.supine(false)],
	]


func _initialize() -> void:
	var ps := poses()
	var sub := SubViewport.new()
	sub.size = Vector2i(int((ps.size() * CELL.x + 20) * ZOOM), int((OUTFITS.size() * CELL.y + 30) * ZOOM))
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub)
	var bg := ColorRect.new()
	bg.color = Color("5c5a54")
	bg.size = Vector2(sub.size)
	sub.add_child(bg)
	var holder := Node2D.new()
	holder.scale = Vector2(ZOOM, ZOOM)
	sub.add_child(holder)
	for i in ps.size():
		var l := Label.new()
		l.text = ps[i][0]
		l.position = Vector2(10 + i * CELL.x, 2) * ZOOM
		l.add_theme_font_size_override("font_size", 22)
		sub.add_child(l)
	for row in OUTFITS.size():
		var lk := Look.look_of(Look.unpack(12345 + row * 7))
		lk.wear = Items.wear_draw(OUTFITS[row])
		for i in ps.size():
			var f := Fig.new()
			f.lk = lk
			f.st = ps[i][1]
			f.top = ps[i][2] if ps[i].size() > 2 else {}
			var sleeper: bool = not f.top.is_empty() and f.top.mode == "supine"
			f.position = Vector2(12 + i * CELL.x + CELL.x * 0.5, 30 + row * CELL.y + (CELL.y - 16 if sleeper and f.top.head_up else (4.0 if sleeper else CELL.y - 10)))
			holder.add_child(f)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := "user://lookbook.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	sub.get_texture().get_image().save_png(out)
	print("lookbook: ", ProjectSettings.globalize_path(out) if out.begins_with("user://") else out)
	quit()
