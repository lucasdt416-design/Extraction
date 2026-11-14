class_name Squad
extends RefCounted

# The shared brain of a group of enemies. Individuals perceive and act; the
# squad is where what they know is pooled and where they are coordinated:
#
#   - One last-known position for the whole squad. Enemies fight where they
#     last saw or heard you, not where you actually are, so breaking line of
#     sight and relocating genuinely works -- and they go and look.
#   - Attack tokens. Only a couple of members may fire at once; the rest
#     reposition. That is what keeps a five-on-one survivable and makes the
#     squad read as taking turns covering each other.
#   - Roles. Anchors hold a firing position, flankers work round a side,
#     pushers close the distance -- hardest when you reload or heal.
#   - Barks. Every coordinated decision is announced, because a flank you were
#     warned about feels smart and one you weren't feels like a cheat.

enum Mode { CALM, INVESTIGATE, COMBAT, SEARCH }

const BARKS: Dictionary = {
	"contact": ["Contact!", "Hostile sighted.", "Intruder, on me!"],
	"flank": ["Flanking.", "Going round the side."],
	"suppress": ["Suppressing.", "Keep them pinned."],
	"reload": ["Reloading.", "Cover me."],
	"grenade": ["Grenade out."],
	"lost": ["Lost visual.", "Where did they go?"],
	"search": ["Sweep the area.", "Check the corners."],
	"clear": ["Nothing here. Resume patrol."],
	"down": ["Unit down!", "We lost one."],
	"push": ["They're exposed. Push.", "Move up, now."],
	"heard": ["Heard something.", "Checking a noise."],
	"hit": ["Taking fire!", "I'm hit."],
	"command_down": ["Command is down. Hold together."],
	"backup": ["Shots fired nearby. Moving to assist."],
}

# Every squad in the raid, so one in a fight can call the others in.
static var all: Array[Squad] = []

var members: Array[Enemy] = []
var points: Array = []
var mode: Mode = Mode.CALM
var last_known: Vector3 = Vector3.ZERO
# Seconds since any member last saw the player.
var contact_age: float = 999.0
var rng := RandomNumberGenerator.new()

var _tokens: Array[Enemy] = []
var _claims: Dictionary = {}
var _search_left: float = 0.0
var _bark_cooldown: float = 0.0
var _lost_announced: bool = false
var _push_announced: bool = false
var _backup_in: float = -1.0
var _backup_at: Vector3 = Vector3.ZERO

func _init(patrol_points: Array, stream_seed: int) -> void:
	points = patrol_points
	rng.seed = stream_seed
	all.append(self)

func living() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for member in members:
		if is_instance_valid(member) and not member.is_dead:
			out.append(member)
	return out

func center() -> Vector3:
	var alive := living()
	if alive.is_empty():
		return last_known
	var sum := Vector3.ZERO
	for member in alive:
		sum += member.global_position
	return sum / alive.size()

# Called once per physics tick by the raid.
func tick(delta: float) -> void:
	_bark_cooldown = maxf(_bark_cooldown - delta, 0.0)
	contact_age += delta
	if _backup_in >= 0.0:
		_backup_in -= delta
		if _backup_in < 0.0 and mode == Mode.CALM and not living().is_empty():
			bark(living()[0], "backup")
			_start_search(_backup_at, 30.0)
	match mode:
		Mode.COMBAT:
			if contact_age > 2.5 and not _lost_announced:
				_lost_announced = true
				_bark_any("lost")
			if contact_age > 9.0:
				_bark_any("search")
				_start_search(last_known, 24.0)
		Mode.SEARCH, Mode.INVESTIGATE:
			_search_left -= delta
			if _search_left <= 0.0:
				_bark_any("clear")
				_set_mode(Mode.CALM)

# --- Reports from members ----------------------------------------------------

func report_sighting(by: Enemy, position: Vector3) -> void:
	last_known = position
	contact_age = 0.0
	_lost_announced = false
	if mode != Mode.COMBAT:
		bark(by, "contact")
		Sfx.play_at("alert", by.global_position, 2.0)
		_enter_combat()

# A noise or a body: not proof, so it earns a look rather than a firefight.
func report_noise(by: Enemy, position: Vector3) -> void:
	match mode:
		Mode.COMBAT:
			# Mid-fight a sound is as good as a sighting for where to push.
			if contact_age > 1.0:
				last_known = position
		Mode.SEARCH:
			last_known = position
			_assign_search_points()
		_:
			bark(by, "heard")
			last_known = position
			_search_left = 14.0
			_set_mode(Mode.INVESTIGATE)
			# The nearest two go and look; the rest stop and face it.
			var alive := living()
			alive.sort_custom(func(a: Enemy, b: Enemy) -> bool:
				return a.global_position.distance_squared_to(position) < b.global_position.distance_squared_to(position))
			for i in alive.size():
				alive[i].investigate(position, i < 2)

func report_hit(by: Enemy, from_position: Vector3) -> void:
	if mode != Mode.COMBAT or contact_age > 1.5:
		last_known = from_position
		contact_age = minf(contact_age, 1.0)
	if mode != Mode.COMBAT:
		bark(by, "hit")
		_enter_combat()

func report_death(member: Enemy, killer: Node) -> void:
	release_token(member)
	_claims.erase(member)
	var alive := living()
	if alive.is_empty():
		return
	bark(alive[0], "command_down" if member.arch.get("commander", false) else "down")
	if killer is Node3D and mode != Mode.COMBAT:
		last_known = (killer as Node3D).global_position
		contact_age = 1.0
		_enter_combat()
	else:
		assign_roles()

func _enter_combat() -> void:
	_set_mode(Mode.COMBAT)
	_push_announced = false
	assign_roles()
	# Nearby squads hear the shooting and come to look a few seconds later.
	for other in all:
		if other != self and other.mode == Mode.CALM and other.center().distance_to(last_known) < 42.0:
			other._backup_in = other.rng.randf_range(4.0, 8.0)
			other._backup_at = last_known

# Sent in from outside the fight: go to where the trouble was and sweep it.
func respond_to(position: Vector3) -> void:
	_start_search(position, 45.0)

func _start_search(around: Vector3, duration: float) -> void:
	last_known = around
	_search_left = duration
	_set_mode(Mode.SEARCH)
	_assign_search_points()

func _set_mode(new_mode: Mode) -> void:
	mode = new_mode
	_tokens.clear()
	_claims.clear()
	var alive := living()
	for i in alive.size():
		alive[i].on_squad_mode(mode, i)

# --- Coordination ------------------------------------------------------------

func assign_roles() -> void:
	var holders := 0
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var announced := false
	for member in living():
		if float(member.arch["aggression"]) >= 0.7:
			member.role = &"push"
		elif holders % 2 == 1:
			member.role = &"flank"
			member.flank_side = side
			side = -side
			if not announced:
				announced = true
				bark(member, "flank")
		else:
			member.role = &"anchor"
		if member.role != &"push":
			holders += 1

func max_tokens() -> int:
	var alive := living()
	var count := 1 if alive.size() <= 1 else 2
	for member in alive:
		if member.arch.get("commander", false):
			count += 1
	return count

func request_token(member: Enemy) -> bool:
	if _tokens.has(member):
		return true
	for i in range(_tokens.size() - 1, -1, -1):
		if not is_instance_valid(_tokens[i]) or _tokens[i].is_dead:
			_tokens.remove_at(i)
	if _tokens.size() >= max_tokens():
		return false
	_tokens.append(member)
	return true

func release_token(member: Enemy) -> void:
	_tokens.erase(member)

# True in the moments the squad should close in: the player is reloading,
# healing or badly hurt, or has gone to ground long enough to be dug out.
func should_push(player: Player) -> bool:
	var push := (player != null and player.is_vulnerable() and contact_age < 2.0) or (contact_age > 3.5 and contact_age < 9.0)
	if push and not _push_announced and contact_age < 2.0:
		_push_announced = true
		_bark_any("push")
	if not push:
		_push_announced = false
	return push

func claim(member: Enemy, position: Vector3) -> void:
	_claims[member] = position

# How crowded a spot is, counting everyone else's claimed positions.
func crowding(member: Enemy, position: Vector3) -> float:
	var total := 0.0
	for other: Enemy in _claims:
		if other == member or not is_instance_valid(other) or other.is_dead:
			continue
		var distance: float = (_claims[other] as Vector3).distance_to(position)
		if distance < 4.0:
			total += 4.0 - distance
	return total

func search_point() -> Vector3:
	var angle := rng.randf() * TAU
	return last_known + Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(3.0, 14.0)

func _assign_search_points() -> void:
	for member in living():
		member.search(search_point())

# --- Barks -------------------------------------------------------------------

func bark(member: Enemy, key: String) -> void:
	if _bark_cooldown > 0.0 or not is_instance_valid(member):
		return
	_bark_cooldown = 1.6
	var lines: Array = BARKS[key]
	var line: String = lines[rng.randi() % lines.size()]
	member.get_tree().call_group("hud", "show_comm", member.arch["name"], line, member.global_position)

func _bark_any(key: String) -> void:
	var alive := living()
	if not alive.is_empty():
		bark(alive[rng.randi() % alive.size()], key)
