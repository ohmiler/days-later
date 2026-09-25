extends SceneTree
## The other half of test_net: joins the host, changes a few things, and
## writes what it saw to user://net_client.txt for the host to check.

var main: Node
var t := 0.0
var step := 0
var lines := []


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(d: float) -> bool:
	t += d
	match step:
		0:
			if t > 0.5:
				step = 1
				var args := OS.get_cmdline_user_args()
				main.port = int(args[0])
				main.player_name = "Client"
				main.ui.secret_override = "client-secret-0123456789abcdef0123"
				if args.size() > 1 and args[1] == "old":
					main.protocol = main.PROTOCOL - 1  # pretend to be an out-of-date copy
					step = 10
				main.ui.appearance = {skin = 2, hair = 3, style = 1, shirt = 4, pants = 2, build = 2}
				main._join("127.0.0.1")
		1:
			if main.in_game and main.players.size() >= 2 and t > 2.5:
				step = 2
				main.ui.chat_sent.emit("hello from the client")
		2:
			if t > 4.5:
				var me: Player = main.players.get(main.multiplayer.get_unique_id())
				lines.append("players %d" % main.players.size())
				lines.append("zombies %d" % main.zombies.size())
				lines.append("own_code %d" % me.app_code)
				for p: Player in main.players.values():
					if p != me:
						lines.append("host_name %s" % p.pname)
						lines.append("host_said %s" % p.say)
				lines.append("box %d" % main.ui.gear.box_id)
				var f := FileAccess.open("user://net_client.txt", FileAccess.WRITE)
				f.store_string("\n".join(lines))
				f.close()
				return true
		10:
			if t > 3.0:
				var f := FileAccess.open("user://net_client.txt", FileAccess.WRITE)
				f.store_string("\n".join(["in_game %s" % main.in_game, "status %s" % main.ui.status.text]))
				f.close()
				return true
	return t > 20.0
