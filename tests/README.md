# Tests

Automated checks that the game still works after a change. Each `test_*.gd`
starts a real game with no window, does things, and checks the results.
They use the `test` save slot, so they never touch your real save.

## Run all of them

From the project folder (change the path to wherever your Godot is):

```
"C:\Users\Miler\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . -s res://tests/run_all.gd
```

It prints one line per file and ends with `ALL PASSED` or the files that failed,
with each failed check underneath. Takes about 15 seconds.

Only some: add `-- name`, e.g. `... -s res://tests/run_all.gd -- inventory`.

## What they cover

| File | Checks |
|---|---|
| `test_actions` | What E does through the real path: doors, searching and reopening furniture, stomping, picking up, nothing out of reach |
| `test_beds` | Sleeping heals (faster shut in), the night speeds up when everyone sleeps, moving or a zombie wakes you, a claimed bed is where you wake after dying |
| `test_city` | The city from a seed is exactly the same as before (saved cities depend on it), every door can be walked to |
| `test_combat` | Punch/kick/weapon hits, clicking the body, knock-downs, cut-off arms, weapon wear, death styles |
| `test_things` | Taps run dry, radios draw zombies, vending machines break open; only changes are saved, they survive a reload, joiners get them |
| `test_zombie` | The telegraphed bite, interrupting it, armour, chasing, getting back up |
| `test_inventory` | Stack sizes, quick heal, drag/merge/split/drop, clothes slots, backpack size |
| `test_doors` | Opening, not shutting on someone, boarding, smashing windows |
| `test_save` | Save and resume: doors, furniture contents, day/time, player, bag, clothes |
| `test_items` | The item table in data/items.cfg has no typos, rare finds are rarer, tags, carrying too much slows you |
| `test_migration` | Old save formats upgrade (and the old file is kept), a damaged save loads from `.bak`, unreadable or newer saves are never written over, "new city" keeps the old one |
| `test_identity` | A name belongs to whoever made it (by their copy's secret), others get a variation, old saves are claimed by the first, an out-of-date copy is turned away |
| `test_net` | A second process joins over the network: names, looks, chat, snapshots, opening a cupboard |

## Writing a new one

Make `tests/test_something.gd`:

```gdscript
extends "res://tests/test_base.gd"

func run() -> void:
	await host(9310)          # a fresh game (pick an unused port)
	var z := zombie_at(me.position + Vector2(14, 0))
	simulate(1.0)             # one second of server time
	check(me.hp < 100.0, "the zombie bit me")
```

`test_base.gd` has the helpers: `host`, `close_game`, `zombie_at`, `simulate`,
`wait`, `frames`, `check`, `bag`, `count`.
