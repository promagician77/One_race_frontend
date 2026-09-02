extends Node
## Central game state. Every screen reads from here and listens for changes.
## In M1 this is local-only. In M4 the mutations route through the server and
## this becomes a cache of server truth — the signal API stays identical, so
## no screen has to change.

signal cash_changed(new_amount: int)
signal neighborhood_changed(neighborhood_id: String)
signal garage_changed()
signal active_car_changed(car_id: String)

## The server owns the truth. Everything below is a cache of what it last
## told us, kept so screens can render without a round trip per label.
##
## Read helpers (can_afford, parking_limit, can_shop_in, ...) answer from that
## cache, which is fine: they exist to grey out buttons before a request is
## sent. Every rule they check is enforced again server-side, so a stale cache
## can only ever produce a refusal the player could have got anyway.
##
## Mutations go to the server and apply what comes back. None of them change
## local state on their own.
const SAVE_PATH := "user://save.json"

var player := {
	"id": "",
	"username": "",
	"cash": 3500,
	"neighborhood": "HARBOUR",
	"street_credit": 0,
	"rank": "Noob",
	"total_races": 0,
	"wins": 0,
}

var garage: Array = []          ## Array of car dictionaries
var active_car_id: String = ""

# ─────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	if not load_game():
		_new_player()


func _new_player() -> void:
	player.id = _uuid()
	player.username = "Racer"
	player.cash = Catalog.starting_cash()
	player.neighborhood = "HARBOUR"
	garage = []
	active_car_id = ""
	save_game()

# ─────────────────────────────────────────────────────────────
# CASH
# ─────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────
# SERVER SYNC
# ─────────────────────────────────────────────────────────────

## Pull the player and their garage from the server. Called after sign-in and
## any time the cache might be stale.
func hydrate() -> Dictionary:
	var me: Dictionary = await Api.refresh_me()
	if not me.ok:
		return me

	_apply_player(me.data.get("player", {}))

	var g: Dictionary = await Api.fetch_garage()
	if not g.ok:
		return g

	_apply_garage(g.data)
	garage_changed.emit()
	save_game()
	return {"ok": true}


## The server speaks camelCase and a flat car; the client's screens were built
## against snake_case with parts and tune grouped. Translating here keeps that
## difference in one place instead of spread across every screen.
## A string from the server, treating JSON null as absent.
##
## Dictionary.get()'s default only applies when the key is missing. The server
## sends activeCarId as null for a player with no car, so str() on it produced
## the literal text "<null>" -- which is not empty, so every "has an active
## car" check passed and every lookup for it failed.
func _text(source: Dictionary, key: String, fallback: String = "") -> String:
	var raw = source.get(key, null)
	return fallback if raw == null else str(raw)


func _apply_player(p: Dictionary) -> void:
	if p.is_empty():
		return
	var before_cash: int = int(player.get("cash", 0))
	var before_hood: String = str(player.get("neighborhood", ""))

	player.id = _text(p, "id", str(player.get("id", "")))
	player.username = _text(p, "username", str(player.get("username", "")))
	player.cash = int(p.get("cash", 0))
	player.neighborhood = _text(p, "neighborhood", "HARBOUR")
	player.street_credit = int(p.get("streetCredit", 0))
	player.rank = _text(p, "rank", "Noob")
	player.total_races = int(p.get("totalRaces", 0))
	player.wins = int(p.get("wins", 0))

	var server_active := _text(p, "activeCarId")
	if server_active != "" and server_active != active_car_id:
		active_car_id = server_active
		active_car_changed.emit(active_car_id)

	if int(player.cash) != before_cash:
		cash_changed.emit(int(player.cash))
	if str(player.neighborhood) != before_hood:
		neighborhood_changed.emit(str(player.neighborhood))


func _apply_garage(cars: Array) -> void:
	garage.clear()
	for c in cars:
		garage.append(_car_from_server(c))


## Replace one car in the cache, or add it if it is new.
func _apply_car(server_car: Dictionary) -> void:
	if server_car.is_empty():
		return
	var car := _car_from_server(server_car)
	var idx := _car_index(str(car.id))
	if idx >= 0:
		garage[idx] = car
	else:
		garage.append(car)


func _car_from_server(c: Dictionary) -> Dictionary:
	return {
		"id": _text(c, "id"),
		"model_id": _text(c, "modelId"),
		"nickname": _text(c, "nickname"),
		"paint_color": _text(c, "paintColor", "#1A1A1A"),
		"plate": _text(c, "plate"),
		"impounded": bool(c.get("impounded", false)),
		"installed": {
			"engine": _text(c, "engineId"),
			"intake": _text(c, "intakeId"),
			"exhaust": _text(c, "exhaustId"),
			"turbo": _text(c, "turboId"),
			"nitrous": _text(c, "nitrousId"),
			"tires": _text(c, "tiresId"),
			"suspension": _text(c, "suspensionId"),
			"trans": _text(c, "transId"),
			"body": _text(c, "bodyId"),
		},
		"tune": {
			"gear_ratios": c.get("gearRatios", []),
			"final_drive": float(c.get("finalDrive", 4.10)),
			"launch_rpm": int(c.get("launchRpm", 0)),
			"shift_points": c.get("shiftPoints", []),
			"tire_pressure": float(c.get("tirePressure", 32.0)),
			"clutch_release": float(c.get("clutchRelease", 0.5)),
			"afr": float(c.get("afr", 14.7)),
			"compression": float(c.get("compression", 9.5)),
			"nitrous_point": float(c.get("nitrousPoint", 0.0)),
		},
		"condition": {
			"engine_health": float(c.get("engineHealth", 100.0)),
			"stress_accum": float(c.get("stressAccum", 0.0)),
			"passes_since_rebuild": int(c.get("passesSinceRebuild", 0)),
		},
		"best_et": c.get("bestEt", null),
		"best_ts": c.get("bestTs", null),
	}


## Turn an Api failure into the { ok, reason } shape the screens already read.
func _refused(res: Dictionary) -> Dictionary:
	return {"ok": false, "reason": str(res.get("message", "That did not work."))}


func can_afford(amount: int) -> bool:
	return player.cash >= amount


func spend(amount: int) -> bool:
	if not can_afford(amount):
		return false
	player.cash -= amount
	cash_changed.emit(player.cash)
	save_game()
	return true


func earn(amount: int) -> void:
	player.cash += amount
	cash_changed.emit(player.cash)
	save_game()


## Set cash to an absolute value. Used when the server reports the balance
## after a transaction — the server is authoritative, so this overwrites
## rather than adjusts.
func set_cash(amount: int) -> void:
	if player.cash == amount:
		return
	player.cash = amount
	cash_changed.emit(amount)
	save_game()

# ─────────────────────────────────────────────────────────────
# NEIGHBORHOOD
# ─────────────────────────────────────────────────────────────

func current_neighborhood() -> Dictionary:
	return Catalog.get_neighborhood(player.neighborhood)


func parking_limit() -> int:
	return current_neighborhood().get("parkingSpaces", 1)


func parking_used() -> int:
	return garage.size()


func has_parking_space() -> bool:
	return parking_used() < parking_limit()


## Can the player shop in this neighborhood? Own rank or below only.
func can_shop_in(neighborhood_id: String) -> bool:
	var mine: int = Catalog.get_neighborhood(player.neighborhood).get("rank", 0)
	var theirs: int = Catalog.get_neighborhood(neighborhood_id).get("rank", 99)
	return theirs <= mine


func can_move_to(neighborhood_id: String) -> Dictionary:
	var target := Catalog.get_neighborhood(neighborhood_id)
	if target.is_empty():
		return {"ok": false, "reason": "That neighborhood doesn't exist."}

	var cost: int = target.get("moveInCost", 0)
	var cur_rank: int = current_neighborhood().get("rank", 0)
	var new_rank: int = target.get("rank", 0)

	if new_rank == cur_rank:
		return {"ok": false, "reason": "You already live here."}

	# Moving up costs money
	if new_rank > cur_rank:
		if not can_afford(cost):
			return {"ok": false, "reason": "You need %s to move in." % Design.fmt_cash(cost)}
		return {"ok": true, "cost": cost, "impound": 0}

	# Moving down is free but may impound cars over the new limit
	var over: int = max(0, garage.size() - target.get("parkingSpaces", 1))
	return {"ok": true, "cost": 0, "impound": over}


## Moving is a paid, permanent decision, so the server decides it. The local
## check first is only to avoid a pointless round trip.
func move_to(neighborhood_id: String) -> Dictionary:
	var check := can_move_to(neighborhood_id)
	if not check.ok:
		return check

	var res: Dictionary = await Api.move_to(neighborhood_id)
	if not res.ok:
		return _refused(res)

	_apply_player(res.data.get("player", {}))

	# Moving down impounds whatever no longer fits, so the garage the server
	# holds is not the one we cached a moment ago.
	var g: Dictionary = await Api.fetch_garage()
	if g.ok:
		_apply_garage(g.data)

	neighborhood_changed.emit(neighborhood_id)
	garage_changed.emit()
	save_game()
	return {"ok": true, "cost": check.get("cost", 0), "impound": check.get("impound", 0)}


# ─────────────────────────────────────────────────────────────
# GARAGE
# ─────────────────────────────────────────────────────────────

## The server takes the money and creates the car. The checks here run first
## purely so an obvious refusal costs nothing; the server enforces them again.
func buy_car(model_id: String) -> Dictionary:
	var model := Catalog.get_car_model(model_id)
	if model.is_empty():
		return {"ok": false, "reason": "Car not found."}

	if not can_shop_in(model.dealership):
		return {"ok": false, "reason": "You can't buy from that neighborhood yet."}

	if not has_parking_space():
		return {"ok": false, "reason": "No parking space. Sell a car or move up."}

	if not can_afford(model.price):
		return {"ok": false, "reason": "You need %s for this car." % Design.fmt_cash(model.price)}

	var res: Dictionary = await Api.buy_car(model_id)
	if not res.ok:
		return _refused(res)

	_apply_car(res.data.get("car", {}))
	set_cash(int(res.data.get("cash", player.cash)))

	if active_car_id == "":
		var bought := str(res.data.get("car", {}).get("id", ""))
		if bought != "":
			await set_active_car(bought)

	garage_changed.emit()
	save_game()
	return {"ok": true, "car": get_car(str(res.data.get("car", {}).get("id", "")))}


func sell_car(car_id: String) -> Dictionary:
	if _car_index(car_id) < 0:
		return {"ok": false, "reason": "Car not found."}

	var res: Dictionary = await Api.sell_car(car_id)
	if not res.ok:
		return _refused(res)

	var idx := _car_index(car_id)
	if idx >= 0:
		garage.remove_at(idx)

	set_cash(int(res.data.get("cash", player.cash)))

	if active_car_id == car_id:
		active_car_id = str(garage[0].id) if garage.size() > 0 else ""
		active_car_changed.emit(active_car_id)

	garage_changed.emit()
	save_game()
	return {"ok": true, "refund": int(res.data.get("refund", 0))}


func set_active_car(car_id: String) -> Dictionary:
	if _car_index(car_id) < 0:
		return {"ok": false, "reason": "Car not found."}

	var res: Dictionary = await Api.set_active_car(car_id)
	if not res.ok:
		return _refused(res)

	_apply_player(res.data.get("player", {}))
	active_car_id = car_id
	active_car_changed.emit(car_id)
	save_game()
	return {"ok": true}


# ─────────────────────────────────────────────────────────────
# PARTS AND TUNING
#
# Thin passes to the server. The car that comes back is authoritative --
# installing a part changes cash, weight, airflow and stress at once, and
# recomputing any of that here would be a second implementation to drift.
# ─────────────────────────────────────────────────────────────

func install_part(car_id: String, part_id: String) -> Dictionary:
	var res: Dictionary = await Api.install_part(car_id, part_id)
	if not res.ok:
		return _refused(res)
	_apply_car(res.data.get("car", {}))
	set_cash(int(res.data.get("cash", player.cash)))
	garage_changed.emit()
	save_game()
	return {"ok": true, "stats": res.data.get("stats", {})}


func remove_part(car_id: String, category: String) -> Dictionary:
	var res: Dictionary = await Api.remove_part(car_id, category)
	if not res.ok:
		return _refused(res)
	_apply_car(res.data.get("car", {}))
	garage_changed.emit()
	save_game()
	return {"ok": true, "stats": res.data.get("stats", {})}


func tune_car(car_id: String, tune: Dictionary) -> Dictionary:
	var res: Dictionary = await Api.tune_car(car_id, tune)
	if not res.ok:
		return _refused(res)
	_apply_car(res.data.get("car", {}))
	garage_changed.emit()
	save_game()
	return {"ok": true, "stats": res.data.get("stats", {})}


func release_from_impound(car_id: String) -> Dictionary:
	var res: Dictionary = await Api.release_from_impound(car_id)
	if not res.ok:
		return _refused(res)
	_apply_car(res.data.get("car", {}))
	set_cash(int(res.data.get("cash", player.cash)))
	garage_changed.emit()
	save_game()
	return {"ok": true}


func get_car(car_id: String) -> Dictionary:
	var idx := _car_index(car_id)
	return garage[idx] if idx >= 0 else {}


func get_active_car() -> Dictionary:
	return get_car(active_car_id)


func _car_index(car_id: String) -> int:
	for i in garage.size():
		if garage[i].get("id", "") == car_id:
			return i
	return -1


# ─────────────────────────────────────────────────────────────
# PERSISTENCE
#
# A cache, not a save file. The server holds the real player and garage; this
# only lets the game draw something familiar before the first response lands.
# Nothing here is trusted: hydrate() overwrites all of it on sign-in.
# ─────────────────────────────────────────────────────────────

func save_game() -> void:
	var data := {
		"version": 1,
		"player": player,
		"garage": garage,
		"active_car_id": active_car_id,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Could not open save file for writing.")
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false

	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false

	var raw := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(raw)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file is corrupt. Starting fresh.")
		return false

	player = parsed.get("player", player)
	garage = parsed.get("garage", [])
	active_car_id = parsed.get("active_car_id", "")
	return true


func reset() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_new_player()
	garage_changed.emit()
	cash_changed.emit(player.cash)

# ─────────────────────────────────────────────────────────────
# UTIL
# ─────────────────────────────────────────────────────────────

func _uuid() -> String:
	var chars := "0123456789abcdef"
	var out := ""
	for i in 32:
		out += chars[randi() % 16]
		if i in [7, 11, 15, 19]:
			out += "-"
	return out


func _plate() -> String:
	var letters := "ABCDEFGHJKLMNPRSTUVWXYZ"
	var out := ""
	for i in 3:
		out += letters[randi() % letters.length()]
	out += str(randi() % 900 + 100)
	return out
