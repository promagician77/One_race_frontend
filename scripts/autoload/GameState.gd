extends Node
## Central game state. Every screen reads from here and listens for changes.
## In M1 this is local-only. In M4 the mutations route through the server and
## this becomes a cache of server truth — the signal API stays identical, so
## no screen has to change.

signal cash_changed(new_amount: int)
signal neighborhood_changed(neighborhood_id: String)
signal garage_changed()
signal active_car_changed(car_id: String)

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


func move_to(neighborhood_id: String) -> Dictionary:
	var check := can_move_to(neighborhood_id)
	if not check.ok:
		return check

	if check.get("cost", 0) > 0:
		spend(check.cost)

	player.neighborhood = neighborhood_id

	# Impound anything over the new limit — oldest cars stay, newest go
	var limit: int = parking_limit()
	if garage.size() > limit:
		for i in range(limit, garage.size()):
			garage[i]["impounded"] = true

	neighborhood_changed.emit(neighborhood_id)
	garage_changed.emit()
	save_game()
	return check

# ─────────────────────────────────────────────────────────────
# GARAGE
# ─────────────────────────────────────────────────────────────

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

	spend(model.price)

	var car := _build_car(model)
	garage.append(car)

	if active_car_id == "":
		set_active_car(car.id)

	garage_changed.emit()
	save_game()
	return {"ok": true, "car": car}


func sell_car(car_id: String) -> Dictionary:
	var idx := _car_index(car_id)
	if idx < 0:
		return {"ok": false, "reason": "Car not found."}

	var car: Dictionary = garage[idx]
	var model := Catalog.get_car_model(car.model_id)

	# 60% of base price back, plus 40% of installed part value
	var refund: int = int(model.get("price", 0) * 0.60)
	for cat in car.installed:
		var pid: String = car.installed[cat]
		if pid != "":
			var part := Catalog.get_part(pid)
			refund += int(part.get("price", 0) * 0.40)

	garage.remove_at(idx)
	earn(refund)

	if active_car_id == car_id:
		active_car_id = garage[0].id if garage.size() > 0 else ""
		active_car_changed.emit(active_car_id)

	garage_changed.emit()
	save_game()
	return {"ok": true, "refund": refund}


func set_active_car(car_id: String) -> void:
	if _car_index(car_id) < 0:
		return
	active_car_id = car_id
	active_car_changed.emit(car_id)
	save_game()


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


func _build_car(model: Dictionary) -> Dictionary:
	var gears: int = model.get("gearCount", 5)
	return {
		"id": _uuid(),
		"model_id": model.id,
		"nickname": model.name,
		"paint_color": "#1A1A1A",
		"plate": _plate(),
		"impounded": false,
		"installed": {
			"engine": "", "intake": "", "exhaust": "", "turbo": "",
			"nitrous": "", "tires": "", "suspension": "", "trans": "", "body": "",
		},
		"tune": {
			"gear_ratios": _default_gears(gears),
			"final_drive": 4.10,
			"launch_rpm": int(model.get("redline", 7000) * 0.45),
			"shift_points": _default_shifts(gears, model.get("redline", 7000)),
			"tire_pressure": 32.0,
			"clutch_release": 0.5,
			"afr": 14.7,
			"compression": 9.5,
			"nitrous_point": 0.0,
		},
		"condition": {
			"engine_health": 100.0,
			"stress_accum": 0.0,
			"passes_since_rebuild": 0,
		},
		"best_et": null,
		"best_ts": null,
	}


func _default_gears(count: int) -> Array:
	var full := [3.30, 2.10, 1.50, 1.15, 0.92, 0.76]
	return full.slice(0, count)


func _default_shifts(count: int, redline: int) -> Array:
	var pts := []
	for i in range(count - 1):
		pts.append(int(redline * 0.92))
	return pts

# ─────────────────────────────────────────────────────────────
# PERSISTENCE
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
