extends Node
## M1 integration gate: the Godot client authenticating against the real
## server and driving a full session over HTTP.
##
## Requires the API running on localhost:3000.
##   cd server && npm start
##   godot --headless --path client tests/IntegrationTest.tscn

var _pass := 0
var _fail := 0
var _failures: Array = []


func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		_failures.append(label)
		print("  FAIL  %s%s" % [label, ("  — " + detail) if detail else ""])


func _section(n: String) -> void:
	print("\n%s" % n)


func _ready() -> void:
	print("\n=== CLIENT -> SERVER INTEGRATION ===")
	await _run()
	print("\n" + "=".repeat(48))
	print("  %d passed, %d failed" % [_pass, _fail])
	if _fail > 0:
		print("\n  Failures:")
		for f in _failures:
			print("    - %s" % f)
	print("=".repeat(48) + "\n")
	get_tree().quit(1 if _fail > 0 else 0)


func _run() -> void:
	Api.sign_out()

	# ── reachability ──────────────────────────────────────────
	_section("Reachability")

	var models := await Api.fetch_car_models()
	if not models.ok:
		_check("server is reachable", false,
			"%s — start it with: cd server && npm start" % models.message)
		return
	_check("server is reachable", true)
	_check("catalog returns 12 car models", models.data.size() == 12,
		str(models.data.size()))

	var parts := await Api.fetch_parts()
	_check("catalog returns 48 parts", parts.ok and parts.data.size() == 48)

	var hoods := await Api.fetch_neighborhoods()
	_check("catalog returns 5 neighborhoods", hoods.ok and hoods.data.size() == 5)

	var tree := await Api.fetch_tree_config()
	_check("staging tree config fetched", tree.ok and tree.data.get("ambers") == 3)

	# ── auth ──────────────────────────────────────────────────
	_section("Auth")

	var uname := "godot_%d" % (Time.get_unix_time_from_system() * 1000)

	var bad := await Api.register("ab", "shortpw")
	_check("server rejects a bad signup", not bad.ok)
	_check("rejection carries a usable message", bad.message.length() > 5, bad.message)

	var reg := await Api.register(uname, "correcthorse42")
	_check("register succeeds", reg.ok, reg.message)
	_check("client is now signed in", Api.is_signed_in())
	_check("token looks like a JWT", Api.token.split(".").size() == 3)
	_check("player starts with $3,500", int(Api.player.get("cash", 0)) == 3500,
		str(Api.player.get("cash")))

	var me := await Api.refresh_me()
	_check("authenticated /auth/me works", me.ok)
	_check("username round-trips", Api.player.get("username", "") == uname)

	# ── economy over the wire ─────────────────────────────────
	_section("Economy")

	var garage := await Api.fetch_garage()
	_check("garage starts empty", garage.ok and garage.data.size() == 0)

	var locked := await Api.buy_car("cm_exotic_hyper")
	_check("locked dealership refused", not locked.ok and locked.code == "SHOP_LOCKED",
		locked.code)

	var broke := await Api.buy_car("cm_coupe_import")
	_check("unaffordable car refused", not broke.ok and broke.code == "INSUFFICIENT_FUNDS",
		broke.code)

	var bought := await Api.buy_car("cm_hatch_kei")
	_check("buying the Bantam succeeds", bought.ok, bought.message)
	_check("server cash synced into GameState", GameState.player.cash == 2300,
		str(GameState.player.cash))

	var car_id: String = bought.data.car.id

	var full := await Api.buy_car("cm_sedan_base")
	_check("parking limit enforced server-side",
		not full.ok and full.code == "NO_PARKING_SPACE", full.code)

	# ── parts and flow sync ───────────────────────────────────
	_section("Parts and flow sync")

	var stats := await Api.fetch_stats(car_id)
	_check("stats fetched", stats.ok)
	_check("stats carry a sync score", stats.data.has("syncScore"))
	_check("stats carry a dyno curve",
		stats.data.get("dynoCurve", []).size() > 5)
	var stock_hp: int = int(stats.data.get("peakHp", 0))

	var wrong_class := await Api.install_part(car_id, "pt_susp_t4")
	_check("incompatible part refused", not wrong_class.ok, wrong_class.code)

	var intake := await Api.install_part(car_id, "pt_intake_t1")
	_check("compatible part installs", intake.ok, intake.message)
	_check("install returns updated stats",
		int(intake.data.stats.peakHp) > stock_hp,
		"%d vs %d" % [int(intake.data.stats.peakHp), stock_hp])

	var exhaust := await Api.install_part(car_id, "pt_exh_t1")
	_check("matching exhaust installs", exhaust.ok)

	# ── tuning ────────────────────────────────────────────────
	_section("Tuning")

	var tuned := await Api.tune_car(car_id, {"afr": 12.5, "launchRpm": 3400})
	_check("tune persists", tuned.ok and float(tuned.data.car.afr) == 12.5)

	var clamped := await Api.tune_car(car_id, {"tirePressure": 999})
	_check("out-of-range value clamped", float(clamped.data.car.tirePressure) == 40.0,
		str(clamped.data.car.tirePressure))

	var dyno := await Api.run_dyno(car_id)
	_check("dyno runs", dyno.ok and dyno.data.dynoCurve.size() > 5)

	# ── racing ────────────────────────────────────────────────
	_section("Racing")

	var green := Time.get_unix_time_from_system() * 1000.0
	var race := await Api.run_practice(car_id, {
		"greenAt": green,
		"launchAt": green + 220,
		"throttleEvents": [],
		"shiftEvents": [],
	})
	_check("practice pass runs", race.ok, race.message)

	if race.ok:
		var lane: Dictionary = race.data.lanes[0]
		_check("reaction time measured", abs(float(lane.rt) - 0.22) < 0.01, str(lane.rt))
		_check("ET returned", float(lane.et) > 8.0 and float(lane.et) < 25.0, str(lane.et))
		_check("trap speed returned", float(lane.ts) > 40.0, str(lane.ts))
		_check("60ft split returned", float(lane.sixtyFt) > 0.0)
		_check("playback trace returned", lane.trace.size() > 50, str(lane.trace.size()))

		var first: Dictionary = lane.trace[0]
		_check("trace points carry rpm, gear, speed",
			first.has("rpm") and first.has("gear") and first.has("speed"))

	var red := await Api.run_practice(car_id, {
		"greenAt": green, "launchAt": green - 100,
		"throttleEvents": [], "shiftEvents": [],
	})
	_check("red light detected server-side", red.ok and red.data.lanes[0].redLight)

	# ── moving ────────────────────────────────────────────────
	_section("Moving")

	var moved := await Api.move_to("NORTHRIDGE")
	_check("move succeeds", moved.ok, moved.message)
	_check("neighborhood updated on the client",
		Api.player.get("neighborhood", "") == "NORTHRIDGE")

	var now_ok := await Api.install_part(car_id, "pt_intake_t3")
	_check("Northridge part unlocked after moving", now_ok.ok, now_ok.message)

	# ── leaderboard ───────────────────────────────────────────
	_section("Leaderboard")

	var board := await Api.fetch_leaderboard()
	_check("leaderboard fetched", board.ok)
	_check("our pass appears on it", board.data.size() > 0)

	# ── session handling ──────────────────────────────────────
	_section("Session")

	var saved := Api.token
	Api.token = "not.a.real.token"
	var rejected := await Api.fetch_garage()
	_check("bad token rejected", not rejected.ok and rejected.code == "UNAUTHORIZED",
		rejected.code)
	_check("client signs out on 401", not Api.is_signed_in())

	Api.token = saved
	var restored := await Api.fetch_garage()
	_check("valid token works again", restored.ok)

	var real_base := Api.base_url
	Api.base_url = "http://localhost:59999"
	var unreachable := await Api.fetch_car_models()
	_check("unreachable server fails gracefully",
		not unreachable.ok and unreachable.code == "NETWORK", unreachable.code)
	_check("network error has a human message",
		unreachable.message.contains("server"), unreachable.message)
	Api.base_url = real_base

	# ── the real screens drive a real session ─────────────────
	# The Api layer is exercised above; this drives the screens a player
	# actually touches, so broken wiring in the UI cannot pass silently.
	_section("Login and sign-up screens")

	Api.sign_out()

	# Router needs somewhere to put the screen it navigates to on success,
	# the way Main provides one at runtime.
	var host := Control.new()
	add_child(host)
	Router.register_container(host)

	var su_packed: PackedScene = load("res://scenes/auth/SignupScreen.tscn")
	var signup: Control = su_packed.instantiate()
	add_child(signup)
	await get_tree().process_frame

	var screen_user := "screen_%d" % (Time.get_unix_time_from_system() * 1000)
	signup._name_field.text = screen_user
	signup._email_field.text = "%s@example.com" % screen_user
	signup._pass_field.text = "correcthorse42"
	signup._confirm_field.text = "correcthorse42"
	await signup._on_submit()

	_check("sign-up screen creates a real account", Api.is_signed_in())
	_check("server issued a real token for it",
		Api.token.split(".").size() == 3)

	Api.sign_out()
	signup._confirm_field.text = "not-the-same"
	await signup._on_submit()
	_check("mismatched confirmation never reaches the server",
		not Api.is_signed_in())
	_check("and the screen says why",
		signup.notice_label.text.contains("match"), signup.notice_label.text)

	signup.queue_free()
	await get_tree().process_frame

	var packed: PackedScene = load("res://scenes/auth/AuthScreen.tscn")
	var screen: Control = packed.instantiate()
	add_child(screen)
	await get_tree().process_frame

	Api.sign_out()
	screen._name_field.text = screen_user
	screen._pass_field.text = "correcthorse42"
	await screen._on_submit()
	_check("logging back in from the login screen works", Api.is_signed_in())

	Api.sign_out()
	screen._name_field.text = screen_user
	screen._pass_field.text = "wrong-password"
	await screen._on_submit()
	_check("wrong password is refused", not Api.is_signed_in())
	_check("and the screen explains why", screen.notice_label.text.length() > 0,
		screen.notice_label.text)

	screen._name_field.text = ""
	screen._pass_field.text = ""
	await screen._on_submit()
	_check("empty fields are caught before any request",
		screen.notice_label.text.contains("racer name"), screen.notice_label.text)

	screen._on_create_account()
	await get_tree().process_frame
	_check("CREATE ACCOUNT opens the sign-up screen",
		Router.current() == Router.Screen.SIGNUP)

	screen.queue_free()
	await get_tree().process_frame
