class_name NetCodec
## Packing what moves into bytes for the snapshots (see Net.send_snapshots):
## positions to half a pixel in 16 bits, an aim to a byte of angle, flags to
## bits. What a snapshot carries for each player is only what everyone needs
## to draw them; names, looks and clothes go once, when they change
## (Net.player_info), and hunger, thirst and the like only to their owner.

const POS_SCALE := 2.0  # positions in half pixels: to 16383 px (a zone is well under)


static func put_pos(b: StreamPeerBuffer, p: Vector2) -> void:
	b.put_u16(clampi(roundi(p.x * POS_SCALE), 0, 65535))
	b.put_u16(clampi(roundi(p.y * POS_SCALE), 0, 65535))


static func get_pos(b: StreamPeerBuffer) -> Vector2:
	var x := b.get_u16()
	return Vector2(x, b.get_u16()) / POS_SCALE


static func angle_byte(v: Vector2) -> int:
	return posmod(roundi(v.angle() / TAU * 256.0), 256)


static func byte_angle(a: int) -> Vector2:
	return Vector2.from_angle(a / 256.0 * TAU)


# --- Players: what everyone sees ----------------------------------------------------

const P_SPRINT := 1
const P_SNEAK := 2
const P_ROOF := 4
const P_SLEEP := 8
const P_AIM := 16
const P_UP := 32
const P_PRONE := 64
const P_SPENT := 128
const P_BLEED := 256


static func put_player(b: StreamPeerBuffer, p: Player) -> void:
	b.put_u32(p.peer_id)
	put_pos(b, p.position)
	b.put_u8(angle_byte(p.aim))
	b.put_u8(clampi(ceili(p.hp), 0, 255))
	b.put_u16(Items.index_of(p.weapon_id))
	b.put_u8(clampi(roundi(p.stamina), 0, 255))
	var f := (P_SPRINT if p.sprint else 0) | (P_SNEAK if p.sneak else 0) | (P_ROOF if p.on_roof else 0) \
			| (P_SLEEP if p.sleeping else 0) | (P_AIM if p.aiming else 0) | (P_UP if p.up else 0) \
			| (P_PRONE if p.prone else 0) | (P_SPENT if p.exhausted else 0) | (P_BLEED if p.bleeding else 0)
	b.put_u16(f)
	b.put_16(p.riding)
	b.put_u8(p.seat)
	b.put_16(p.sitting)
	b.put_u8(p.rest_face)
	b.put_16(p.on_car)
	b.put_32(p.grabbed_by)
	b.put_u8(clampi(roundi(p.struggle * 255.0), 0, 255))


## The next player in `b` as a dictionary (Net.snapshot applies it).
static func get_player(b: StreamPeerBuffer) -> Dictionary:
	var d := {id = b.get_u32(), pos = get_pos(b), aim = byte_angle(b.get_u8()) * 40.0, hp = float(b.get_u8()),
			weapon = Items.id_at(b.get_u16()), stamina = float(b.get_u8())}
	var f := b.get_u16()
	d.sprint = f & P_SPRINT != 0
	d.sneak = f & P_SNEAK != 0
	d.on_roof = f & P_ROOF != 0
	d.sleeping = f & P_SLEEP != 0
	d.aiming = f & P_AIM != 0
	d.up = f & P_UP != 0
	d.prone = f & P_PRONE != 0
	d.exhausted = f & P_SPENT != 0
	d.bleeding = f & P_BLEED != 0
	d.riding = b.get_16()
	d.seat = b.get_u8()
	d.sitting = b.get_16()
	d.rest_face = b.get_u8()
	d.on_car = b.get_16()
	d.grabbed_by = b.get_32()
	d.struggle = b.get_u8() / 255.0
	return d


# --- Players: only their owner ------------------------------------------------------

static func own_bytes(p: Player, world: World) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(clampi(roundi(p.hunger), 0, 255))
	b.put_u8(clampi(roundi(p.thirst), 0, 255))
	b.put_u8(clampi(roundi(p.infection), 0, 255))
	b.put_u16(clampi(p.kills, 0, 65535))
	b.put_32(p.bed)
	b.put_32(p.sleep_bed)
	b.put_float(world.vehicles[p.riding].fuel if p.riding >= 0 and p.riding < world.vehicles.size() else 0.0)
	return b.data_array


static func read_own(data: PackedByteArray) -> Dictionary:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	return {hunger = float(b.get_u8()), thirst = float(b.get_u8()), infection = float(b.get_u8()), kills = b.get_u16(),
			bed = b.get_32(), sleep_bed = b.get_32(), fuel = b.get_float()}


# --- Zombies ------------------------------------------------------------------------

## A zombie in 13 bytes: id, where, health, what it's up to (state 0-2 and
## flags 1 lunging, 2 down, 4 upstairs, 8 holding someone) and what it's lost.
static func zombie_bytes(z: Zombie) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(z.zid)
	put_pos(b, z.position)
	b.put_u8(clampi(ceili(z.hp), 0, 255))
	b.put_u8((z.state & 3) | ((z.flags & 15) << 2))
	b.put_u8(z.missing & 255)
	return b.data_array


static func get_zombie(b: StreamPeerBuffer) -> Dictionary:
	var d := {id = b.get_u32(), pos = get_pos(b), hp = float(b.get_u8())}
	var s := b.get_u8()
	d.state = s & 3
	d.flags = s >> 2
	d.missing = b.get_u8()
	return d


const ZOMBIE_BYTES := 13


## A zombie that has only moved and changed what it's doing since `was`
## (the bytes last sent): 7 bytes, the id and how far it went in half pixels.
## Empty when that won't do (its health or limbs changed, or it went too far).
static func nudge(was: PackedByteArray, now: PackedByteArray) -> PackedByteArray:
	if was[8] != now[8] or was[10] != now[10]:
		return PackedByteArray()
	var a := StreamPeerBuffer.new()
	a.data_array = was
	var b := StreamPeerBuffer.new()
	b.data_array = now
	a.seek(4)
	b.seek(4)
	var dx := b.get_u16() - a.get_u16()
	var dy := b.get_u16() - a.get_u16()
	if absi(dx) > 127 or absi(dy) > 127:
		return PackedByteArray()
	var out := StreamPeerBuffer.new()
	out.data_array = now.slice(0, 4)
	out.seek(4)
	out.put_8(dx)
	out.put_8(dy)
	out.put_u8(now[9])
	return out.data_array


static func get_nudge(b: StreamPeerBuffer) -> Dictionary:
	var d := {id = b.get_u32()}
	var dx := b.get_8()
	d.move = Vector2(dx, b.get_8()) / POS_SCALE
	var s := b.get_u8()
	d.state = s & 3
	d.flags = s >> 2
	return d


# --- Playing it back smoothly (client) ----------------------------------------------

const INTERP := 0.12  # s: others are shown this far in the past, between two snapshots
const EXTRAPOLATE := 0.15  # s: at most this far past the newest one (a late or lost snapshot)
const SAMPLES := 8


## Add where something was at server time `t` to `samples` ([[t, pos], ...]).
static func push(samples: Array, t: float, pos: Vector2) -> void:
	if not samples.is_empty() and t <= samples[-1][0]:
		return  # (out of order, or the same moment again)
	samples.append([t, pos])
	if samples.size() > SAMPLES:
		samples.pop_front()


## Where it was at time `t`: between the two samples either side; past the
## newest, carried on a little the way it was going. INF with nothing yet.
static func sample_at(samples: Array, t: float) -> Vector2:
	if samples.is_empty():
		return Vector2.INF
	if t <= samples[0][0]:
		return samples[0][1]
	for i in range(samples.size() - 1, 0, -1):
		var a: Array = samples[i - 1]
		var b: Array = samples[i]
		if t >= a[0] and t <= b[0]:
			return (a[1] as Vector2).lerp(b[1], (t - a[0]) / maxf(b[0] - a[0], 0.0001))
	var last: Array = samples[-1]
	if samples.size() < 2:
		return last[1]
	var prev: Array = samples[-2]
	var v: Vector2 = ((last[1] as Vector2) - prev[1]) / maxf(last[0] - prev[0], 0.0001)
	return (last[1] as Vector2) + v * minf(t - last[0], EXTRAPOLATE)
