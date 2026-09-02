extends Node

const CARS_PATH  := "res://data/car_models.json"
const PARTS_PATH := "res://data/parts.json"
const HOOD_PATH  := "res://data/neighborhoods.json"

var _car_models: Array = []
var _parts: Array = []
var _neighborhoods: Array = []
var _impound: Dictionary = {}
var _starting_cash: int = 3500

# Lookup indices, built once
var _car_by_id: Dictionary = {}
var _part_by_id: Dictionary = {}
var _hood_by_id: Dictionary = {}


func _ready() -> void:
	_load_all()

func _load_all() -> void:
	var cars := _read_json(CARS_PATH)
	_car_models = cars.get("models", [])

	var parts := _read_json(PARTS_PATH)
	_parts = parts.get("parts", [])

	var hoods := _read_json(HOOD_PATH)
	_neighborhoods = hoods.get("neighborhoods", [])
	_impound = hoods.get("impound", {})
	_starting_cash = hoods.get("startingCash", 3500)

	for m in _car_models:
		_car_by_id[m.id] = m
	for p in _parts:
		_part_by_id[p.id] = p
	for h in _neighborhoods:
		_hood_by_id[h.id] = h

	print("[Catalog] %d cars, %d parts, %d neighborhoods" % [
		_car_models.size(), _parts.size(), _neighborhoods.size()])


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing data file: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Malformed JSON: %s" % path)
		return {}
	return parsed

# ─────────────────────────────────────────────────────────────
# CARS
# ─────────────────────────────────────────────────────────────

func all_car_models() -> Array:
	return _car_models


func get_car_model(id: String) -> Dictionary:
	return _car_by_id.get(id, {})


## Cars sold at a given dealership, cheapest first.
func cars_in(neighborhood_id: String) -> Array:
	var out := _car_models.filter(func(m): return m.dealership == neighborhood_id)
	out.sort_custom(func(a, b): return a.price < b.price)
	return out

# ─────────────────────────────────────────────────────────────
# PARTS
# ─────────────────────────────────────────────────────────────

func all_parts() -> Array:
	return _parts


## Parts stocked in a given neighborhood, cheapest first. Mirrors cars_in --
## availability is gated by neighborhood, not by which shop pin you clicked.
func parts_in(neighborhood_id: String) -> Array:
	var out := _parts.filter(func(p): return p.neighborhood == neighborhood_id)
	out.sort_custom(func(a, b): return a.price < b.price)
	return out


func get_part(id: String) -> Dictionary:
	return _part_by_id.get(id, {})


## Parts in a category, filtered to what this car class can use and what
## this neighborhood stocks. Sorted by tier.
func parts_for(category: String, car_class: String, neighborhood_id: String) -> Array:
	var out := _parts.filter(func(p):
		return p.category == category \
			and car_class in p.compatibleClasses \
			and p.neighborhood == neighborhood_id
	)
	out.sort_custom(func(a, b): return a.tier < b.tier)
	return out


## Every part in a category this car class can use, across all shops the
## player has access to. Used for the shop list with lock states.
func parts_available_to(category: String, car_class: String, player_hood: String) -> Array:
	var rank: int = get_neighborhood(player_hood).get("rank", 0)
	var out := _parts.filter(func(p):
		if p.category != category:
			return false
		if not car_class in p.compatibleClasses:
			return false
		return true
	)
	# Annotate lock state rather than filtering — the player should see what's
	# coming, they just can't buy it yet. Window shopping was in the original.
	for p in out:
		p["_locked"] = get_neighborhood(p.neighborhood).get("rank", 99) > rank
	out.sort_custom(func(a, b): return a.tier < b.tier)
	return out


func part_categories() -> Array:
	return ["ENGINE", "INTAKE", "EXHAUST", "TURBO", "NITROUS",
			"TIRES", "SUSPENSION", "TRANS", "BODY"]


## Which categories have at least one part this car can use.
func active_categories_for(car_class: String) -> Array:
	var out := []
	for cat in part_categories():
		for p in _parts:
			if p.category == cat and car_class in p.compatibleClasses:
				out.append(cat)
				break
	return out

# ─────────────────────────────────────────────────────────────
# NEIGHBORHOODS
# ─────────────────────────────────────────────────────────────

func all_neighborhoods() -> Array:
	return _neighborhoods


func get_neighborhood(id: String) -> Dictionary:
	return _hood_by_id.get(id, {})


func impound_config() -> Dictionary:
	return _impound


func starting_cash() -> int:
	return _starting_cash


# ─────────────────────────────────────────────────────────────
# CAR PHOTOGRAPHS
#
# One place decides what a car looks like. The dealership worked this out for
# itself, so the garage and the part shop were falling back to the procedural
# placeholder sprites and showing a flat silhouette of a car the showroom had
# a photograph of.
# ─────────────────────────────────────────────────────────────

const CAR_SHOT_DIR := "res://assets/ui/cars/"

var _shot_count := -1


## The photograph for a car model.
##
## A file named for the model's own `spriteSet` wins, so renaming a shot to
## bantam_gx.png pins it to that car for good. Anything without one is dealt a
## numbered shot by its position in the catalog, which is stable between runs.
func car_shot(model: Dictionary) -> Texture2D:
	if model.is_empty():
		return null

	var named := "%s%s.png" % [CAR_SHOT_DIR, str(model.get("spriteSet", ""))]
	if ResourceLoader.exists(named):
		return load(named)

	var total := car_shot_count()
	if total == 0:
		return null
	return load("%s%d.png" % [CAR_SHOT_DIR, (_model_index(model) % total) + 1])


## How many numbered shots ship. Counted once.
func car_shot_count() -> int:
	if _shot_count < 0:
		_shot_count = 0
		while ResourceLoader.exists("%s%d.png" % [CAR_SHOT_DIR, _shot_count + 1]):
			_shot_count += 1
	return _shot_count


func _model_index(model: Dictionary) -> int:
	var models: Array = all_car_models()
	for i in models.size():
		if str(models[i].get("id", "")) == str(model.get("id", "")):
			return i
	return 0

