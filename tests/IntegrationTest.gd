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


	# ── GameState is backed by the server ─────────────────────
	# The point of the state layer: nothing the player owns lives only in the
	# client. Every check here reads back what the server stored, not what the
	# client hoped it stored.
	_section("Server-backed state")

	Api.sign_out()
	var st_user := "state_%d" % (Time.get_unix_time_from_system() * 1000)
	var st_made: Dictionary = await Api.register(st_user, "correcthorse42", "%s@example.com" % st_user)
	_check("registered for the state test", st_made.ok, str(st_made.get("message", "")))

	GameState.reset()
	var st_hydrated: Dictionary = await GameState.hydrate()
	_check("hydrate pulls the player", st_hydrated.get("ok", false),
		str(st_hydrated.get("reason", st_hydrated.get("message", ""))))
	_check("cash came from the server", int(GameState.player.cash) == 3500,
		str(GameState.player.cash))
	_check("garage starts empty on the server", GameState.garage.size() == 0)

	var st_bought: Dictionary = await GameState.buy_car("cm_hatch_kei")
	_check("buying goes through the server", st_bought.get("ok", false),
		str(st_bought.get("reason", "")))
	_check("the car is in the local cache", GameState.garage.size() == 1)
	_check("cash reflects the server's figure", int(GameState.player.cash) == 2300,
		str(GameState.player.cash))
	_check("the first car became active", GameState.active_car_id != "")

	var st_car_id: String = str(GameState.garage[0].id)
	_check("the car kept its server id", st_car_id.length() > 0)
	_check("the car was translated into the client's shape",
		GameState.garage[0].has("model_id") and GameState.garage[0].has("installed")
			and GameState.garage[0].has("tune"),
		str(GameState.garage[0].keys()))

	var st_tuned: Dictionary = await GameState.tune_car(st_car_id, {"afr": 12.5})
	_check("tuning goes through the server", st_tuned.get("ok", false),
		str(st_tuned.get("reason", "")))
	_check("the tune came back applied",
		abs(float(GameState.get_car(st_car_id).tune.afr) - 12.5) < 0.001,
		str(GameState.get_car(st_car_id).tune.afr))

	# The real proof: throw the cache away and ask the server again.
	GameState.reset()
	_check("cache cleared", GameState.garage.size() == 0)
	await GameState.hydrate()
	_check("the car survives a cleared cache", GameState.garage.size() == 1,
		str(GameState.garage.size()))
	_check("so does the tune",
		abs(float(GameState.garage[0].tune.afr) - 12.5) < 0.001,
		str(GameState.garage[0].tune.afr))
	_check("so does the cash", int(GameState.player.cash) == 2300,
		str(GameState.player.cash))

	var st_sold: Dictionary = await GameState.sell_car(st_car_id)
	_check("selling goes through the server", st_sold.get("ok", false),
		str(st_sold.get("reason", "")))
	_check("the garage empties", GameState.garage.size() == 0)
	_check("the refund landed", int(GameState.player.cash) > 2300,
		str(GameState.player.cash))


	# ── M2 gate: fitting parts changes the airflow match ───────
	# The milestone's wording: "buy a car, install parts, run the dyno, watch
	# flow sync change the HP curve." All of it inside a starting player's
	# $3,500 -- and the Bantam GX shows the whole thesis on its own, because
	# the T2 pair costs three times the T1 pair and makes less power with it.
	_section("Flow sync")

	Api.sign_out()
	var fs_user := "sync_%d" % (Time.get_unix_time_from_system() * 1000)
	await Api.register(fs_user, "correcthorse42", "%s@example.com" % fs_user)
	GameState.reset()
	await GameState.hydrate()

	var fs_bought: Dictionary = await GameState.buy_car("cm_hatch_kei")   # $1,200
	_check("bought a car to work on", fs_bought.get("ok", false),
		str(fs_bought.get("reason", "")))
	var fs_car: String = str(GameState.garage[0].id) if GameState.garage.size() > 0 else ""
	_check("the car has an id", fs_car != "")

	var fs_stock: Dictionary = await Api.fetch_stats(fs_car)
	_check("stock car reports a match score",
		fs_stock.ok and fs_stock.data.has("syncScore"), str(fs_stock.get("message", "")))
	var fs_stock_hp: int = int(fs_stock.data.get("peakHp", 0))
	var fs_stock_sync: int = int(fs_stock.data.get("syncScore", 0))

	# A bare engine still breathes, badly: flow is capped below what it wants.
	_check("a stock car is slightly starved",
		int(fs_stock.data.systemAirFlow) < int(fs_stock.data.engineAirNeed),
		"%d cfm vs %d wanted" % [int(fs_stock.data.systemAirFlow),
			int(fs_stock.data.engineAirNeed)])

	# The cheap matched pair. Both halves matter: the air path is a chain, so
	# upgrading one end alone changes nothing.
	var fit_in: Dictionary = await GameState.install_part(fs_car, "pt_intake_t1")
	_check("fitting the intake goes through the server", fit_in.get("ok", false),
		str(fit_in.get("reason", "")))

	var half: Dictionary = await Api.fetch_stats(fs_car)
	_check("an intake alone does not raise system flow, the exhaust still caps it",
		int(half.data.systemAirFlow) == int(fs_stock.data.systemAirFlow),
		"%d -> %d cfm" % [int(fs_stock.data.systemAirFlow), int(half.data.systemAirFlow)])

	var fit_ex: Dictionary = await GameState.install_part(fs_car, "pt_exh_t1")
	_check("fitting the exhaust goes through the server", fit_ex.get("ok", false),
		str(fit_ex.get("reason", "")))

	var fs_t1: Dictionary = await Api.fetch_stats(fs_car)
	var t1_hp: int = int(fs_t1.data.peakHp)
	var t1_sync: int = int(fs_t1.data.syncScore)
	_check("with both ends done the system flows more air",
		int(fs_t1.data.systemAirFlow) > int(fs_stock.data.systemAirFlow),
		"%d -> %d cfm" % [int(fs_stock.data.systemAirFlow), int(fs_t1.data.systemAirFlow)])
	_check("the match improves", t1_sync > fs_stock_sync,
		"%d -> %d" % [fs_stock_sync, t1_sync])
	_check("and the car makes more power", t1_hp > fs_stock_hp,
		"%d -> %d hp" % [fs_stock_hp, t1_hp])

	# The dearer pair. More airflow than this engine can use.
	var up_in: Dictionary = await GameState.install_part(fs_car, "pt_intake_t2")
	_check("fitting the pricier intake works", up_in.get("ok", false),
		str(up_in.get("reason", "")))
	var up_ex: Dictionary = await GameState.install_part(fs_car, "pt_exh_t2")
	_check("fitting the pricier exhaust works", up_ex.get("ok", false),
		str(up_ex.get("reason", "")))

	var fs_t2: Dictionary = await Api.fetch_stats(fs_car)
	var t2_hp: int = int(fs_t2.data.peakHp)
	var t2_sync: int = int(fs_t2.data.syncScore)

	_check("the pricier pair over-flows the engine",
		int(fs_t2.data.systemAirFlow) > int(fs_t2.data.engineAirNeed),
		"%d cfm into an engine wanting %d" % [int(fs_t2.data.systemAirFlow),
			int(fs_t2.data.engineAirNeed)])
	_check("so the match score collapses", t2_sync < t1_sync,
		"%d -> %d" % [t1_sync, t2_sync])

	# This is the line the whole game rests on.
	_check("and the expensive pair makes LESS power than the cheap one",
		t2_hp < t1_hp, "$920 of parts: %d hp, $330 of parts: %d hp" % [t2_hp, t1_hp])

	# Taking one off has to walk it back, or the shop's REMOVE button lies.
	var stripped: Dictionary = await GameState.remove_part(fs_car, "INTAKE")
	_check("removing a part goes through the server", stripped.get("ok", false),
		str(stripped.get("reason", "")))
	_check("and the slot is empty again",
		str(GameState.get_car(fs_car).installed.intake) == "",
		str(GameState.get_car(fs_car).installed.intake))

	var fs_curve: Dictionary = await Api.run_dyno(fs_car)
	_check("the dyno returns a curve to plot",
		fs_curve.ok and fs_curve.data.get("dynoCurve", []).size() > 0,
		str(fs_curve.data.get("dynoCurve", []).size()))


	# ── the garage panel gets real numbers ────────────────────
	# Its stat rows come from /car/:id/stats. Everything else on that panel
	# reads GameState, so blank stats with a filled OWNED count means the
	# request never landed rather than the panel being wired wrong.
	_section("Garage panel")

	Api.sign_out()
	var g_user := "garage_%d" % (Time.get_unix_time_from_system() * 1000)
	await Api.register(g_user, "correcthorse42", "%s@example.com" % g_user)
	GameState.reset()
	await GameState.hydrate()
	await GameState.buy_car("cm_hatch_kei")

	var g_host := Control.new()
	add_child(g_host)
	Router.register_container(g_host)

	var g_packed: PackedScene = load("res://scenes/garage/Garage.tscn")
	var g_screen: Control = g_packed.instantiate()
	add_child(g_screen)
	# Generous: the screen fetches its stats over HTTP, and HTTPRequest needs
	# frames to poll. If it fills within this and not within six, the screen
	# is fine and the wait was too short.
	for _i in 60:
		await get_tree().process_frame

	# The server sends activeCarId as JSON null for a player with no car.
	# Dictionary.get()'s default only fires when the key is *missing*, so
	# str() on it produced the literal text "<null>" -- not empty, so every
	# "do I have an active car" check passed and every lookup for it failed.
	_check("a null from the server never becomes the text '<null>'",
		not str(GameState.active_car_id).contains("null"),
		GameState.active_car_id)
	_check("the garage picks up the car", GameState.garage.size() == 1,
		str(GameState.garage.size()))
	_check("and selects it", g_screen._selected != "", g_screen._selected)
	# Is it the endpoint, or the screen's call to it?
	var direct: Dictionary = await Api.fetch_stats(str(GameState.garage[0].id))
	_check("the stats endpoint answers", direct.get("ok", false),
		str(direct.get("message", direct.get("code", ""))))
	_check("stats arrived from the server", not g_screen._stats.is_empty(),
		str(g_screen._stats.keys()))
	_check("power is a real figure", int(g_screen._stats.get("peakHp", 0)) > 0,
		str(g_screen._stats.get("peakHp", "missing")))
	_check("the panel shows it rather than a dash",
		g_screen._panel._values[0].text.contains("HP"),
		g_screen._panel._values[0].text)
	_check("and handling reads the grip the server reports",
		g_screen._panel._values[5].text != "—",
		g_screen._panel._values[5].text)

	g_screen.queue_free()
	await get_tree().process_frame

