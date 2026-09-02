extends Node

signal auth_changed(signed_in: bool)
signal request_failed(code: String, message: String)

const CONTRACT_VERSION := "1.0"
const DEFAULT_BASE_URL := "http://127.0.0.1:3000"
const TIMEOUT_SECONDS := 15.0

var base_url: String = DEFAULT_BASE_URL
var token: String = ""
var player: Dictionary = {}

var _pool: Array[HTTPRequest] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--api="):
			base_url = arg.substr(6)

	_load_token()

func is_signed_in() -> bool:
	return token != ""

func register(username: String, password: String, email: String = "") -> Dictionary:
	var body := {"username": username, "password": password}
	if email != "":
		body["email"] = email
	var res := await _http_post("/auth/register", body, false)
	if res.ok:
		_accept_session(res.data)
	return res

func login(username: String, password: String) -> Dictionary:
	var res := await _http_post("/auth/login",
		{"username": username, "password": password}, false)
	if res.ok:
		_accept_session(res.data)
	return res

func refresh_me() -> Dictionary:
	var res := await _http_get("/auth/me")
	if res.ok:
		player = res.data.get("player", {})
	return res

func sign_out() -> void:
	token = ""
	player = {}
	_clear_token()
	auth_changed.emit(false)

func _accept_session(data: Dictionary) -> void:
	token = data.get("token", "")
	player = data.get("player", {})
	_save_token()
	auth_changed.emit(true)
# ─────────────────────────────────────────────────────────────
# CATALOG
# ─────────────────────────────────────────────────────────────

func fetch_car_models() -> Dictionary:
	return await _http_get("/catalog/cars")


func fetch_parts() -> Dictionary:
	return await _http_get("/catalog/parts")


func fetch_neighborhoods() -> Dictionary:
	return await _http_get("/catalog/neighborhoods")


func fetch_tree_config() -> Dictionary:
	return await _http_get("/catalog/tree")

# ─────────────────────────────────────────────────────────────
# GARAGE
# ─────────────────────────────────────────────────────────────

func fetch_garage() -> Dictionary:
	return await _http_get("/player/garage")


func buy_car(model_id: String) -> Dictionary:
	var res := await _http_post("/player/car/buy", {"modelId": model_id})
	if res.ok:
		_sync_cash(res.data.get("cash"))
	return res


func sell_car(car_id: String) -> Dictionary:
	var res := await _http_post("/player/car/sell", {"carId": car_id})
	if res.ok:
		_sync_cash(res.data.get("cash"))
	return res


func set_active_car(car_id: String) -> Dictionary:
	var res := await _http_post("/player/car/active", {"carId": car_id})
	if res.ok:
		player = res.data.get("player", player)
	return res


func move_to(neighborhood_id: String) -> Dictionary:
	var res := await _http_post("/player/move", {"neighborhood": neighborhood_id})
	if res.ok:
		player = res.data.get("player", player)
	return res


func release_from_impound(car_id: String) -> Dictionary:
	var res := await _http_post("/player/impound/release", {"carId": car_id})
	if res.ok:
		_sync_cash(res.data.get("cash"))
	return res

# ─────────────────────────────────────────────────────────────
# CAR
# ─────────────────────────────────────────────────────────────

func fetch_stats(car_id: String) -> Dictionary:
	return await _http_get("/car/%s/stats" % car_id)


func install_part(car_id: String, part_id: String) -> Dictionary:
	var res := await _http_post("/car/%s/part/install" % car_id, {"partId": part_id})
	if res.ok:
		_sync_cash(res.data.get("cash"))
	return res


func remove_part(car_id: String, category: String) -> Dictionary:
	return await _http_post("/car/%s/part/remove" % car_id, {"category": category})


## What a part would do if fitted. Nothing is bought and nothing is changed.
func preview_part(car_id: String, part_id: String) -> Dictionary:
	return await _http_post("/car/%s/part/preview" % car_id, {"partId": part_id})


func tune_car(car_id: String, tune: Dictionary) -> Dictionary:
	return await _http_post("/car/%s/tune" % car_id, {"tune": tune})


func run_dyno(car_id: String) -> Dictionary:
	return await _http_post("/car/%s/dyno" % car_id, {})


func repair_car(car_id: String) -> Dictionary:
	var res := await _http_post("/car/%s/repair" % car_id, {})
	if res.ok:
		_sync_cash(res.data.get("cash"))
	return res

# ─────────────────────────────────────────────────────────────
# RACING
# ─────────────────────────────────────────────────────────────

func run_practice(car_id: String, input: Dictionary) -> Dictionary:
	return await _http_post("/race/practice", {"carId": car_id, "input": input})


func fetch_leaderboard(car_class: String = "", limit: int = 25) -> Dictionary:
	var q := "?limit=%d" % limit
	if car_class != "":
		q += "&class=%s" % car_class
	return await _http_get("/leaderboard" + q)


func fetch_race_history() -> Dictionary:
	return await _http_get("/player/races")

# ─────────────────────────────────────────────────────────────
# TRANSPORT
# ─────────────────────────────────────────────────────────────

func _http_get(path: String, authed: bool = true) -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, path, {}, authed)


func _http_post(path: String, body: Dictionary, authed: bool = true) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, path, body, authed)


func _request(method: int, path: String, body: Dictionary, authed: bool) -> Dictionary:
	var http := _lease()

	var headers := PackedStringArray(["Content-Type: application/json"])
	if authed and token != "":
		headers.append("Authorization: Bearer %s" % token)

	var payload := "" if method == HTTPClient.METHOD_GET else JSON.stringify(body)

	var err := http.request(base_url + path, headers, method, payload)
	if err != OK:
		_release(http)
		return _fail("NETWORK", "Cannot reach the server. Is it running?")

	var result: Array = await http.request_completed

	_release(http)
	return _interpret(result, path)


func _interpret(result: Array, path: String = "") -> Dictionary:
	var http_result: int = result[0]
	var status: int = result[1]
	var headers: PackedStringArray = result[2]
	var raw: PackedByteArray = result[3]

	if http_result != HTTPRequest.RESULT_SUCCESS:
		match http_result:
			HTTPRequest.RESULT_TIMEOUT:
				return _fail("TIMEOUT", "The server took too long to respond.")
			HTTPRequest.RESULT_CANT_RESOLVE:
				return _fail("NETWORK", "Cannot find that server address.")
			HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
				return _fail("NETWORK", "Secure connection to the server failed.")
			_:
				return _fail("NETWORK", "Cannot reach the server. Is it running?")

	# A major contract mismatch means the client is too old to talk to this
	# server. Fail loudly here rather than in a confusing way later.
	for h in headers:
		if h.to_lower().begins_with("x-contract-version:"):
			var served := h.split(":")[1].strip_edges()
			if served.split(".")[0] != CONTRACT_VERSION.split(".")[0]:
				return _fail("CONTRACT_MISMATCH",
					"This client is out of date. Update to keep playing.")

	var text := raw.get_string_from_utf8()
	var parsed = JSON.parse_string(text) if text != "" else {}

	if status >= 200 and status < 300:
		# A proxy or captive portal can hand back HTML with a 200. Treating
		# that as success returned data:null and crashed every caller.
		if parsed == null:
			return _fail("BAD_RESPONSE", "The server sent something unreadable.")
		return {"ok": true, "data": parsed, "code": "", "message": ""}

	# Every server error uses the same envelope
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("error"):
		var e: Dictionary = parsed.error
		var code: String = e.get("code", "UNKNOWN")
		var message: String = e.get("message", "Something went wrong.")

		# Only a rejected TOKEN ends the session. A wrong password on the
		# login form is also UNAUTHORIZED, and it must not delete a stored
		# session that is still perfectly valid.
		var credentials_check := path.begins_with("/auth/login") or path.begins_with("/auth/register")
		if code == "UNAUTHORIZED" and is_signed_in() and not credentials_check:
			sign_out()

		request_failed.emit(code, message)
		return {"ok": false, "data": null, "code": code, "message": message}

	return _fail("UNKNOWN", "Something went wrong (HTTP %d)." % status)


func _fail(code: String, message: String) -> Dictionary:
	request_failed.emit(code, message)
	return {"ok": false, "data": null, "code": code, "message": message}

# HTTPRequest nodes cannot be reused while in flight, so keep a small pool
# rather than allocating one per call.
func _lease() -> HTTPRequest:
	for h in _pool:
		if not h.get_meta("busy", false):
			h.set_meta("busy", true)
			return h
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	http.set_meta("busy", true)
	add_child(http)
	_pool.append(http)
	return http


func _release(http: HTTPRequest) -> void:
	http.set_meta("busy", false)

# ─────────────────────────────────────────────────────────────
# SESSION PERSISTENCE
# ─────────────────────────────────────────────────────────────

const TOKEN_PATH := "user://session.dat"

func _save_token() -> void:
	var f := FileAccess.open(TOKEN_PATH, FileAccess.WRITE)
	if f:
		f.store_line(token)
		f.close()


func _load_token() -> void:
	if not FileAccess.file_exists(TOKEN_PATH):
		return
	var f := FileAccess.open(TOKEN_PATH, FileAccess.READ)
	if f:
		token = f.get_line().strip_edges()
		f.close()


func _clear_token() -> void:
	if FileAccess.file_exists(TOKEN_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TOKEN_PATH))


func _sync_cash(cash) -> void:
	if cash == null:
		return
	# Mirror only. GameState's own wrapper applies the cash AFTER the car —
	# emitting from here fired cash_changed while the garage was still
	# pre-purchase, and listeners reading both saw them disagree.
	player["cash"] = int(cash)
