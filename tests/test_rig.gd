extends "res://tests/test_base.gd"
## The rig (pose -> joints): arms and legs keep their length in every pose and
## view, so nothing stretches, and every leg says where its knee is.

const EPS := 0.05


func run() -> void:
	var views := [[[Look.SIDE, false], 0.0], [[Look.SIDE, true], PI], [[Look.FRONT, false], PI / 2],
			[[Look.BACK, false], -PI / 2], [[Look.SIDE, false], -0.6], [[Look.FRONT, false], 2.2]]
	var weapons := {}
	for id in ["machete", "axe", "bat", "knife"]:
		weapons[id] = Items.def(id).draw
	var poses := [{}, {guard = true}, {moving = true, phase = 1.2}, {moving = true, phase = -2.0}]
	for t in [0.0, 0.15, 0.3, 0.45, 0.6, 0.8, 1.0]:
		poses.append({attack = Look.PUNCH_R, ext = t})
		poses.append({attack = Look.PUNCH_L, ext = t})
		poses.append({attack = Look.KICK, ext = t})
		for id in weapons:
			poses.append({weapon = weapons[id], attack = Look.SWING, ext = t, id = id})
		poses.append({weapon = weapons.machete, weapon_l = weapons.knife, attack = Look.SWING_L, ext = t, id = "pair"})
		poses.append({zombie = true, bite = t})
		poses.append({zombie = true, breed = "runner", moving = true, phase = t * TAU})
	poses.append({zombie = true, moving = true, phase = 1.0, breed = "fat"})
	for u in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]:
		poses.append({zombie = true, rise = u, fall_dir = 1.0})
		poses.append({rise = u, fall_dir = -1.0})
	for t in [0.0, 1.5, 3.0, 4.5]:
		poses.append({zombie = true, moving = true, phase = t, vary = {limp = 1.5, arm_y = 1.0}})
	poses.append({zombie = true, scream = 0.5})

	var arms_bad := []
	var legs_bad := []
	var no_knee := []
	for p in poses:
		for v in views:
			var st: Dictionary = p.duplicate()
			st.view = v[0]
			st.angle = v[1]
			var r := Rig.build(st, {})
			var name := "%s view %d angle %.1f" % [_describe(p), v[0][0], v[1]]
			for a in r.arms_back + r.arms_front:
				var up := (a.elbow as Vector2).distance_to(a.sh)
				var fore := (a.hand as Vector2).distance_to(a.elbow)
				if up > Rig.UPPER_ARM + EPS or fore > Rig.FOREARM + EPS:
					arms_bad.append("%s arm %d: %.1f + %.1f" % [name, a.idx, up, fore])
			for leg in r.legs:
				if not (leg.has("hip") and leg.has("knee") and leg.has("foot")):
					no_knee.append(name)
					continue
				if leg.type == "rect":
					continue  # front/back legs are straight columns, not bent limbs
				var th := (leg.knee as Vector2).distance_to(leg.hip)
				var sh := (leg.foot as Vector2).distance_to(leg.knee)
				if th > Rig.THIGH + EPS or sh > Rig.SHIN + EPS:
					legs_bad.append("%s: %.1f + %.1f" % [name, th, sh])
	check(arms_bad.is_empty(), "arms never stretch (%d poses checked)%s" % [poses.size() * views.size(), _first(arms_bad)])
	check(legs_bad.is_empty(), "legs never stretch" + _first(legs_bad))
	check(no_knee.is_empty(), "every leg has a hip, knee and foot" + _first(no_knee))

	# A bigger build has wider shoulders, so the arms hang off the body, not inside it.
	var thin := Rig.build({view = [Look.FRONT, false]}, {})
	var big := Rig.build({view = [Look.FRONT, false]}, {build = 1.35})
	check(absf(big.arms_front[1].sh.x) > absf(thin.arms_front[1].sh.x) + 1.0, "a big build's shoulders are wider")

	# Idle and fighting use the same shoulders: raising the fists doesn't make them jump.
	for view in [Look.SIDE, Look.FRONT]:
		var idle := Rig.build({view = [view, false]}, {})
		var guard := Rig.build({view = [view, false], guard = true, angle = PI / 2 if view == Look.FRONT else 0.0}, {})
		var same := true
		for i in 2:
			same = same and _arm_by_idx(idle, i).sh.is_equal_approx(_arm_by_idx(guard, i).sh)
		check(same, "shoulders stay put going from idle to guard (view %d)" % view)

	# Two hands on a long weapon: both hands are on the handle.
	for id in ["axe", "bat"]:
		var far := 0.0
		for t in [0.0, 0.2, 0.4, 0.6, 0.8]:
			var r := Rig.build({view = [Look.SIDE, false], weapon = weapons[id], attack = Look.SWING, ext = t}, {})
			var main_arm := _arm_by_idx(r, 1)
			var off := _arm_by_idx(r, 0)
			var dir: Vector2 = main_arm.weapon.dir
			var h: Vector2 = main_arm.hand
			var rel: Vector2 = off.hand - h
			far = maxf(far, absf(rel.cross(dir)))  # how far off the handle's line
		check(far < 0.3, "%s: the other hand stays on the handle (%.2f off)" % [id, far])
		# Facing the camera, held low in both hands: the arms come down to it in a V
		# (left hand left of the right), not folded across the chest.
		var fr := Rig.build({view = [Look.FRONT, false], angle = PI / 2, weapon = weapons[id]}, {})
		var l: Vector2 = _arm_by_idx(fr, 0).hand
		var rh: Vector2 = _arm_by_idx(fr, 1).hand
		check(l.x <= rh.x and l.y > -17.0 and rh.y > -17.0, "%s from the front: held low, arms not crossed (%s, %s)" % [id, l, rh])


	# A punch turns the shoulder into it; the body stays over its hips.
	var pr := Rig.build({view = [Look.SIDE, false], attack = Look.PUNCH_R, ext = 1.0}, {})
	var sh_idle: Vector2 = Rig.shoulders(Look.SIDE)[1]
	check(absf(pr.upper.x) <= 1.0 and _arm_by_idx(pr, 1).sh.x > sh_idle.x + 1.0,
			"punching, the shoulder goes forward, not the whole body (body %.1f)" % pr.upper.x)

	# A zombie throws itself by bending at the hips: the body stays on its legs.
	var zl := Rig.build({view = [Look.SIDE, false], zombie = true, bite = 0.8}, {})
	check(absf(zl.upper.x) <= 1.3 and zl.torso > 0.3, "a lunging zombie bends forward, not slides (body %.1f, bend %.2f)" % [zl.upper.x, zl.torso])

	# Zombies from behind still have arms (reaching away, hands by the shoulders).
	var zb := Rig.build({view = [Look.BACK, false], angle = -PI / 2, zombie = true}, {})
	check((zb.arms_back + zb.arms_front).size() == 2, "a zombie seen from behind has both arms")
	# A limping zombie drags one foot: it never leaves the ground, and swings less.
	var lifted := 0.0
	var swing := [0.0, 0.0]
	for t in 16:
		var r := Rig.build({view = [Look.SIDE, false], zombie = true, moving = true, phase = t * TAU / 16.0,
				vary = {limp = 1.5, arm_y = 1.0}}, {})
		lifted = maxf(lifted, -(r.legs[1].foot as Vector2).y)
		for i in 2:
			swing[i] = maxf(swing[i], absf((r.legs[i].foot as Vector2).x - (r.legs[i].hip as Vector2).x))
	check(lifted < 0.05 and swing[1] < swing[0], "a limping zombie drags its bad foot (lift %.2f, swing %.1f vs %.1f)" % [lifted, swing[1], swing[0]])
	# Getting up: from lying flat, through sitting, to standing.
	var down := Rig.build({view = [Look.SIDE, true], rise = 0.0, fall_dir = 1.0, zombie = true}, {})
	var sit := Rig.build({view = [Look.SIDE, true], rise = 0.4, fall_dir = 1.0, zombie = true}, {})
	var up := Rig.build({view = [Look.SIDE, true], rise = 1.0, fall_dir = 1.0, zombie = true}, {})
	check(is_equal_approx(absf((down.base as Transform2D).get_rotation()), PI / 2) and is_zero_approx((up.base as Transform2D).get_rotation()),
			"getting up starts lying flat and ends standing")
	check(is_zero_approx((sit.base as Transform2D).get_rotation() + (sit.torso as float)), "half way, it sits upright")

	# Easing: raising the fists eases in over BLEND_TIME instead of jumping.
	var mem := {}
	var idle_st := {view = [Look.SIDE, false]}
	var guard_st := {view = [Look.SIDE, false], guard = true}
	var idle_r := Rig.build_eased(idle_st, {}, mem, 10.0)
	var target := Rig.build(guard_st, {})
	Rig.build_eased(guard_st, {}, mem, 10.02)  # the first frame asking for the guard: the ease starts
	var mid := Rig.build_eased(guard_st, {}, mem, 10.02 + Rig.BLEND_TIME * 0.5)
	var h0: Vector2 = _arm_by_idx(idle_r, 1).hand
	var h1: Vector2 = _arm_by_idx(target, 1).hand
	var hm: Vector2 = _arm_by_idx(mid, 1).hand
	check(hm.distance_to(h0) > 0.5 and hm.distance_to(h1) > 0.5, "fists come up part way, not in one frame")
	var ok := true
	for a in mid.arms_back + mid.arms_front:
		ok = ok and (a.elbow as Vector2).distance_to(a.sh) <= Rig.UPPER_ARM + EPS and (a.hand as Vector2).distance_to(a.elbow) <= Rig.FOREARM + EPS
	check(ok, "arms don't stretch part way between poses")
	var done := Rig.build_eased(guard_st, {}, mem, 10.02 + Rig.BLEND_TIME * 1.5)
	check((_arm_by_idx(done, 1).hand as Vector2).is_equal_approx(h1), "and end up exactly in the new pose")
	# Turning to face another way changes the whole drawing at once.
	var front := Rig.build_eased({view = [Look.FRONT, false], angle = PI / 2}, {}, mem, 11.0)
	Rig.build_eased({view = [Look.FRONT, false], angle = PI / 2, guard = true}, {}, mem, 12.0)
	var turned := Rig.build_eased({view = [Look.SIDE, false]}, {}, mem, 12.01)
	check((_arm_by_idx(turned, 1).hand as Vector2).is_equal_approx(h0), "turning around doesn't ease (%s)" % front.view)
	# Standing still, the chest rises and falls; walking, it doesn't breathe on top.
	var b0 := Rig.build({view = [Look.SIDE, false], breath = -PI / 2}, {})
	var b1 := Rig.build({view = [Look.SIDE, false], breath = PI / 2}, {})
	check(absf(b0.upper.y - b1.upper.y) > 0.1, "breathing moves the chest")
	var w0 := Rig.build({view = [Look.SIDE, false], moving = true, phase = 1.0, breath = -PI / 2}, {})
	var w1 := Rig.build({view = [Look.SIDE, false], moving = true, phase = 1.0, breath = PI / 2}, {})
	check(is_equal_approx(w0.upper.y, w1.upper.y), "but not while walking")


func _arm_by_idx(r: Dictionary, i: int) -> Dictionary:
	for a in r.arms_back + r.arms_front:
		if a.idx == i:
			return a
	return {}


func _describe(p: Dictionary) -> String:
	var bits := []
	for k in p:
		if k in ["weapon", "weapon_l"]:
			continue
		bits.append("%s=%s" % [k, p[k]])
	return "{" + ", ".join(bits) + "}"


func _first(list: Array) -> String:
	if list.is_empty():
		return ""
	return " -- %d bad, e.g. %s" % [list.size(), "; ".join(list.slice(0, 3))]
