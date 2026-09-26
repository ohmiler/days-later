extends "res://tests/test_base.gd"
## A big zone that stays quick: only what's around the view is in the scene
## (the rest still exists for the rules), zombies are about around the players
## and drop away where nobody is, and each player is sent only the zombies
## around them.


func run() -> void:
	SaveGame.wipe()
	seed(3)
	await host(9480)
	var w: World = main.world
	check(World.W * World.TILE >= 5000 and World.H * World.TILE >= 3800, "a zone is a good size (%d x %d px)" % [World.W * World.TILE, World.H * World.TILE])

	# Streaming: a headless server has nothing in the scene; a view brings in its surroundings.
	var total := 0
	for list in w.stream.values():
		total += list.size()
	var in_scene := func() -> int:
		var n := 0
		for list in w.stream.values():
			for x: Node in list:
				if x.get_parent() != null:
					n += 1
		return n
	check(in_scene.call() == 0, "with no screen, no props in the scene (%d exist)" % total)
	var view := Rect2(me.position - Vector2(240, 135), Vector2(480, 270))
	for i in 20:
		w.stream_around(view)
	var near: int = in_scene.call()
	check(near > 0 and near < total / 4, "a view brings in what's around it (%d of %d)" % [near, total])
	var far_view := Rect2(Vector2.ZERO, Vector2(480, 270))  # (the far corner from the spawn, near the middle)
	for i in 40:
		w.stream_around(far_view)
	var here := w.near(me.position).filter(func(x): return x.get_parent() != null)
	check(here.is_empty(), "and lets go of it when the view moves far off")
	var out_of_scene: Array = w.container_nodes.filter(func(x): return x.get_parent() == null)
	check(not out_of_scene.is_empty() and out_of_scene[0].data.has("kind"), "what's out of the scene is still there for the rules")

	# Zombies turn up around the player, out of sight, not across the city.
	for z in main.zombies.values():
		z.queue_free()
	main.zombies.clear()
	for i in 30:
		main.survival._spawn_zombie()
	var dists: Array = main.zombies.values().map(func(z): return z.position.distance_to(me.position))
	check(not dists.is_empty() and dists.all(func(d): return d >= 300.0 and d < Main.NEAR), "zombies turn up around you, out of sight (%d)" % dists.size())
	for i in 60:
		main.survival._spawn_zombie()
	check(main.zombies.size() <= Main.MAX_ZOMBIES, "up to so many around you (%d)" % main.zombies.size())

	# One left far from everyone wanders off; one chasing you doesn't.
	var lost := zombie_at(me.position + Vector2(Main.NEAR * 2.0, 0))
	var chaser := zombie_at(me.position + Vector2(-Main.NEAR * 2.0, 0))
	chaser.target = me
	main.survival._despawn_t = 0.0
	main.survival._despawn_far(0.1)
	check(not main.zombies.has(lost.zid), "a zombie far from everyone is dropped")
	check(main.zombies.has(chaser.zid), "but not one that's after someone")

	# Each player is sent the zombies around them (and any after them).
	var mine: Array = main.zombies_for(me).map(func(z): return z.zid)
	check(chaser.zid in mine, "a zombie after you is sent to you even from far off")
	var far := zombie_at(me.position + Vector2(0, Main.NEAR + 200.0))
	check(not far.zid in main.zombies_for(me).map(func(z): return z.zid), "one far off and minding its own business isn't")
