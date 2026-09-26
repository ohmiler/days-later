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
| `test_admin` | The developer panel (F2): conjuring items, healing, zombies of a kind, clearing them, the time; only for the host |
| `test_body` | Bites leave wounds where they land (bruises under armour), bleeding until bandaged, one bandage per wound, open bites festering, healing (faster asleep), sprains stop running, wounds saved |
| `test_city` | The building plans (data/prefabs) are drawn correctly, the city from a seed is exactly the same as before (saved cities depend on it), every door and cupboard can be walked to |
| `test_combat` | Punch/kick/weapon hits, a weapon in each hand swinging in turn, two-handed weapons taking both hands, clicking the body, knock-downs, cut-off arms, weapon wear, death styles, a click while busy still lands, the 1-2 restarts after a pause, hitstop, your own swing shows on the click |
| `test_things` | Taps run dry, radios draw zombies, vending machines break open; only changes are saved, they survive a reload, joiners get them |
| `test_vehicles` | Every bike model has ride data; riding is fast, burns fuel, is loud, knocks zombies down, can't go indoors; hotwiring, refuelling, and bikes stay where left after a reload |
| `test_zombie` | The telegraphed bite, interrupting it, where bites land (arms face to face, neck from behind, legs from the ground) and what guards each part, chasing, getting back up |
| `test_inventory` | Stack sizes, quick heal, drag/merge/split/drop, clothes slots and layers, masks/gloves/knee pads, bags adding slots |
| `test_crafting` | The recipe table has no typos, taking apart, making (standing still), mending, worn clothes never used up, pulling furniture apart |
| `test_doors` | Opening, not shutting on someone, boarding, smashing windows |
| `test_rig` | Arms and legs keep their length in every pose and view (nothing stretches), every leg has a knee, broader builds have wider shoulders, both hands stay on a two-handed weapon, pose changes ease in (without stretching) but turning around doesn't, breathing only when standing still, zombies have arms from behind, limping zombies drag a foot, getting up goes lying → sitting → standing |
| `test_save` | Save and resume: doors, furniture contents, day/time, player, bag, clothes |
| `test_items` | The item table in data/items.cfg has no typos, rare finds are rarer, furniture holds what you'd expect (fridges: food and drink), tags, carrying too much slows you |
| `test_migration` | Old save formats upgrade (and the old file is kept), a damaged save loads from `.bak`, unreadable or newer saves are never written over, "new city" keeps the old one, a city from an older generator moves its survivors to a new one |
| `test_guns` | Reloading from the bag, firing only while aiming, hits, the noise, empty clicks, the gun as a club, shotgun pellets |
| `test_identity` | A name belongs to whoever made it (by their copy's secret), others get a variation, old saves are claimed by the first, an out-of-date copy is turned away |
| `test_net` | A second process joins over the network: names, looks, chat, snapshots, opening a cupboard |

## Speed

`tests/perf.gd` measures how fast the game draws. It needs a real window, so
it isn't part of `run_all` (no `--headless`):

```
"C:\Users\Miler\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path . --resolution 1280x720 -s res://tests/perf.gd
```

It prints draw calls and milliseconds a frame at the normal zoom and zoomed
out, and fails if either goes over its budget. Run it after visual work.

## Writing a new one

A new `class_name` file is only known to Godot after an import: run the game
once from the editor, or `... --headless --path . --import`. (Until then a
test that uses it cannot load and the run waits forever.)


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
