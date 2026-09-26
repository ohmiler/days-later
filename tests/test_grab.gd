extends "res://tests/test_base.gd"
## A zombie can grab hold instead of biting: you can't move or fight, only
## struggle (Space, a click, E) before it bites, harder. Struggle free and it
## staggers back; hit it, knock it down or kill it and it lets go.


func run() -> void:
	SaveGame.wipe()
	seed(9)
	await host(9509)
	main.spawn_timer = 1e9

	var z := zombie_at(me.position + Vector2(10, 0))
	z.grab(me)
	check(me.grabbed_by == z.zid and z.grab_peer == me.peer_id, "a zombie gets hold of you")
	var at := me.position
	me.move = Vector2.LEFT
	simulate(0.3)
	check(me.position.distance_to(at) < 0.5, "held: you can't walk away")
	me.move = Vector2.ZERO
	me.set_attack_input(true, false)
	check(not me.wants_punch(), "or punch it")
	me.set_attack_input(false, false)

	# Struggle free: it staggers back.
	var sta := me.stamina
	for i in 5:
		main.actions.req_struggle()
	check(me.grabbed_by < 0 and z.grab_peer == 0, "five good shoves and you're free")
	check(z.stun > 0.0, "and it staggers")
	check(me.stamina < sta, "struggling takes it out of you")

	# Too slow: it bites, harder.
	me.hp = Player.MAX_HP
	z.stun = 0.0
	z.grab(me)
	simulate(Zombie.GRAB_TIME + 0.2)
	check(me.hp < Player.MAX_HP and me.grabbed_by < 0, "too slow: it bites and lets go (%.0f hp)" % me.hp)

	# Hit by someone else, it lets go.
	z.attack_cd = 0.0
	z.grab(me)
	z.stun = 0.3
	simulate(0.05)
	check(me.grabbed_by < 0, "a friend's blow makes it let go")

	# Killed while holding you: you're free.
	z.stun = 0.0
	z.grab(me)
	main.combat._kill_zombie(z, 1.0)
	simulate(0.05)
	check(me.grabbed_by < 0, "killed, it lets go")

	await close_game()
