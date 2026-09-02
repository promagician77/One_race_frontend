extends Node
## Headless smoke test for M1. Run with:
##   godot --headless --path . tests/SmokeTest.tscn
##
## Runs as a scene rather than --script so the real autoloads (Design,
## Catalog, GameState, Router) are registered exactly as they are at runtime.
## Exercises what a headless boot alone does not touch: economy gates,
## neighborhood rules, save/load, scene loading, and the UI builders.
## Exits non-zero on any failure so CI can gate on it.

## Painted glyph bounds, measured with tools/ArtProbe.gd. Fixtures for the
## mask-coverage checks below.

var _pass := 0
var _fail := 0
var _failures: Array = []


func _ready() -> void:
	print("\n=== M1 SMOKE TEST ===\n")

	_test_catalog(Catalog)
	_test_formatters(Design)
	_test_economy(GameState, Catalog)
	_test_neighborhoods(GameState, Catalog)
	await _test_persistence(GameState)
	_test_scenes(Router)
	_test_uikit()
	await _test_city_map()
	await _test_auth_screen()
	await _test_header()
	await _test_main_scene()
	await _test_boot_is_visible()
	await _test_parts_shop()
	await _test_garage()
	await _test_null_fields()

	_report()


# ─────────────────────────────────────────────────────────────

func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		_failures.append(label)
		print("  FAIL  %s %s" % [label, ("— " + detail) if detail else ""])


func _section(name: String) -> void:
	print("\n%s" % name)


# ─────────────────────────────────────────────────────────────

func _test_catalog(catalog) -> void:
	_section("Catalog")

	_check("12 car models load", catalog.all_car_models().size() == 12,
		"got %d" % catalog.all_car_models().size())
	_check("48 parts load", catalog.all_parts().size() == 48,
		"got %d" % catalog.all_parts().size())
	_check("5 neighborhoods load", catalog.all_neighborhoods().size() == 5)

	var bantam = catalog.get_car_model("cm_hatch_kei")
	_check("lookup by id works", bantam.get("name", "") == "Bantam GX")

	var harbour_cars = catalog.cars_in("HARBOUR")
	_check("Harbour District stocks cars", harbour_cars.size() >= 3)
	_check("dealership list sorted by price",
		harbour_cars[0].price <= harbour_cars[-1].price)

	var import_intakes = catalog.parts_for("INTAKE", "IMPORT", "HARBOUR")
	_check("part filter by class+hood returns results", import_intakes.size() > 0)

	var truck_turbos = catalog.parts_for("TURBO", "TRUCK", "NORTHRIDGE")
	var has_small_only = false
	for p in truck_turbos:
		if p.id == "pt_turbo_t1":
			has_small_only = true
	_check("compact turbo excluded from TRUCK", not has_small_only,
		"pt_turbo_t1 is IMPORT/SPORT only")

	var cats = catalog.active_categories_for("IMPORT")
	_check("IMPORT has all 9 part categories", cats.size() == 9,
		"got %d" % cats.size())


func _test_formatters(design) -> void:
	_section("Formatters")

	_check("fmt_cash adds separators", design.fmt_cash(1234567) == "$1,234,567",
		design.fmt_cash(1234567))
	_check("fmt_cash handles small", design.fmt_cash(500) == "$500",
		design.fmt_cash(500))
	_check("fmt_cash handles zero", design.fmt_cash(0) == "$0")
	_check("fmt_cash handles negative", design.fmt_cash(-250) == "-$250",
		design.fmt_cash(-250))
	_check("fmt_et is 3dp", design.fmt_et(11.43728) == "11.437",
		design.fmt_et(11.43728))
	_check("fmt_rt marks red light", design.fmt_rt(-0.023) == "-0.023",
		design.fmt_rt(-0.023))
	_check("fmt_ts is 1dp", design.fmt_ts(142.73) == "142.7",
		design.fmt_ts(142.73))
	_check("sync_color green in band", design.sync_color(90.0) == design.GOOD)
	_check("sync_color red when starved", design.sync_color(40.0) == design.BAD)


## Buying and selling are server transactions now, so the money and the garage
## are checked in api.test.mjs and the Supabase end-to-end. What stays here is
## the refusal path: every reason the client turns a purchase down before it
## spends a request, and the wording the player is shown for it.
func _test_economy(state, catalog) -> void:
	_section("Economy gates")

	state.reset()
	_check("starts with $3,500", state.player.cash == 3500,
		"got %d" % state.player.cash)
	_check("starts in Harbour District", state.player.neighborhood == "HARBOUR")
	_check("garage starts empty", state.garage.size() == 0)
	_check("can afford a starter car", state.can_afford(1200))
	_check("cannot afford a Downtown car", not state.can_afford(340000))
	_check("one parking space to begin with", state.has_parking_space())

	# Too expensive, but sold locally -- so the funds check is what fires,
	# not the district one.
	var r = await state.buy_car("cm_coupe_import")   # $5,800 vs $3,500
	_check("expensive car blocked by funds", not r.ok)
	_check("funds refusal names the shortfall",
		str(r.get("reason", "")).contains("need"), str(r.get("reason", "")))

	# Sold in a district the player has not moved into yet.
	r = await state.buy_car("cm_exotic_hyper")
	_check("Downtown car blocked from Harbour District", not r.ok)
	_check("locked-district refusal says so",
		str(r.get("reason", "")).contains("neighborhood"), str(r.get("reason", "")))

	# A full garage is refused before anything is charged.
	state.garage = [{"id": "parked"}]
	_check("garage is full at the starting limit", not state.has_parking_space())
	r = await state.buy_car("cm_hatch_kei")
	_check("2nd car blocked by parking limit", not r.ok)
	_check("parking error is specific",
		str(r.get("reason", "")).contains("parking"), str(r.get("reason", "")))
	state.garage = []

	# Nonsense ids never reach the server either.
	r = await state.buy_car("cm_not_a_real_car")
	_check("unknown car refused", not r.ok)

	r = await state.sell_car("not_a_real_id")
	_check("selling a car you do not own is refused", not r.ok)


## The client no longer moves anyone or impounds anything -- the server does,
## and api.test.mjs covers it there. What is still the client's job is
## deciding what to offer: which shops are reachable, how many spaces the
## current district has, and whether a move is worth asking about. Those
## predicates are what this checks.
func _test_neighborhoods(state, catalog) -> void:
	_section("Neighborhood rules")

	state.reset()
	_check("Harbour District parking limit is 1", state.parking_limit() == 1)
	_check("can shop in own hood", state.can_shop_in("HARBOUR"))
	_check("cannot shop up", not state.can_shop_in("EASTPOINT"))

	var check = state.can_move_to("NORTHRIDGE")
	_check("can afford Northridge move", check.ok, str(check.get("reason", "")))
	_check("the move quotes its cost", int(check.get("cost", 0)) == 500,
		str(check.get("cost", 0)))

	check = state.can_move_to("DOWNTOWN")
	_check("Downtown blocked by funds", not check.ok)
	_check("and says why", str(check.get("reason", "")).length() > 0)

	check = state.can_move_to("HARBOUR")
	_check("moving to where you already live is refused", not check.ok)

	# Living in Northridge changes what is reachable and how much fits.
	state.player.neighborhood = "NORTHRIDGE"
	_check("parking limit follows the district", state.parking_limit() == 3)
	_check("can shop down to Harbour District", state.can_shop_in("HARBOUR"))
	_check("still cannot shop up to Eastpoint", not state.can_shop_in("EASTPOINT"))

	# Moving down warns about what will not fit. The server does the
	# impounding; this is the number the player is shown beforehand.
	state.player.cash = 20000
	state.garage = [{"id": "a"}, {"id": "b"}, {"id": "c"}]
	check = state.can_move_to("HARBOUR")
	_check("moving down is allowed", check.ok, str(check.get("reason", "")))
	_check("and warns how many cars will not fit", int(check.get("impound", 0)) == 2,
		"expected 2, got %d" % int(check.get("impound", 0)))
	state.garage = []


func _test_persistence(state) -> void:
	_section("Save / load")

	state.reset()

	# Awaited, not fired and forgotten. buy_car reaches the server now, so an
	# un-awaited call leaves a coroutine running through whichever test comes
	# next and lands its result there -- which is exactly how the part shop's
	# "no car" check started failing at random.
	await state.buy_car("cm_hatch_kei")
	state.earn(5000)
	var cash_before: int = state.player.cash
	var garage_before: int = state.garage.size()
	var active_before: String = state.active_car_id

	state.save_game()

	# Wipe in-memory state, then reload from disk
	state.player.cash = 0
	state.garage = []
	state.active_car_id = ""

	var loaded: bool = state.load_game()
	_check("load_game succeeds", loaded)
	_check("cash restored", state.player.cash == cash_before,
		"expected %d got %d" % [cash_before, state.player.cash])
	_check("garage restored", state.garage.size() == garage_before)
	_check("active car restored", state.active_car_id == active_before)


func _test_scenes(router) -> void:
	_section("Scenes")

	for screen in router.SCENES:
		var path: String = router.SCENES[screen]
		var exists := ResourceLoader.exists(path)
		_check("scene exists: %s" % path.get_file(), exists, path)

		if exists:
			var packed = load(path)
			_check("  instantiates: %s" % path.get_file(),
				packed != null and packed.can_instantiate())


func _test_uikit() -> void:
	_section("UIKit builders")

	var kit = load("res://scripts/ui/UIKit.gd")
	var built: Array = []

	var cases := {
		"panel":        kit.panel(),
		"accent_panel": kit.accent_panel(Color.RED),
		"divider":      kit.divider(),
		"micro_label":  kit.micro_label("TEST"),
		"heading":      kit.heading("Test"),
		"body":         kit.body("Test"),
		"stat_row":     kit.stat_row("Label", "Value"),
		"stat_block":   kit.stat_block("LABEL", "42"),
		"badge":        kit.badge("IMPORT", Color.BLUE),
		"empty_state":  kit.empty_state("None", "Nothing here"),
	}
	for name in cases:
		_check("%s builds" % name, cases[name] != null)
		built.append(cases[name])

	for style in [0, 1, 2, 3]:
		var b = kit.button("Go", style)
		_check("button style %d builds" % style, b != null)
		built.append(b)

	# meter must produce a partial-width fill, not a full bar
	var m = kit.meter(0.5, Color.GREEN)
	_check("meter builds", m != null)
	built.append(m)
	if m != null and m.get_child_count() >= 2:
		var bar = m.get_child(1)
		_check("meter fill respects ratio",
			is_equal_approx(bar.anchor_right, 0.5),
			"anchor_right = %f" % bar.anchor_right)
	else:
		_check("meter has track + fill", false)

	for n in built:
		if is_instance_valid(n):
			n.free()


func _test_city_map() -> void:
	_section("City map")

	GameState.reset()

	var packed: PackedScene = load("res://scenes/map/CityMap.tscn")
	var map = packed.instantiate()
	add_child(map)
	await get_tree().process_frame

	_check("MapArea node present", map.get_node_or_null("Layout/MapArea") != null)

	# The detail panel floats over the map now rather than sitting beside it,
	# so the artwork is never squashed by a column.
	var detail: Node = null
	for child in map.get_children():
		if child is PanelContainer:
			detail = child
	_check("detail panel floats over the map", detail != null)

	var area = map.get_node_or_null("Layout/MapArea")

	# The pins are painted into citymap.png; hotspots are transparent hit
	# areas placed over them, plus the backdrop itself as the first child.
	var spots: Array = []
	var has_backdrop := false
	if area != null:
		for child in area.get_children():
			if child is TextureRect:
				has_backdrop = true
			elif child is Button:
				spots.append(child)
	_check("map backdrop is drawn from the artwork", has_backdrop)
	_check("11 hotspots created", spots.size() == 11, "got %d" % spots.size())

	var invisible := true
	for b in spots:
		if b.text != "":
			invisible = false
	_check("hotspots draw nothing over the painted pins", invisible)

	# Dealerships and part shops each have artwork of their own; the panel
	# serves both and is built for whichever kind was chosen.
	_check("dealership art is present",
		ResourceLoader.exists("res://assets/ui/dealership.png"))
	_check("part shop art is present",
		ResourceLoader.exists("res://assets/ui/partshop.png"))
	_check("map builds the location panel", map._modal is LocationModal)
	_check("the panel stays hidden until a location is chosen",
		not map._modal.visible)

	var dealer: Dictionary = {}
	var shop: Dictionary = {}
	var pound: Dictionary = {}
	var track: Dictionary = {}
	var garage: Dictionary = {}
	for h in map._hotspots:
		if h.data.kind == "DEALERSHIP" and dealer.is_empty():
			dealer = h.data
		elif h.data.kind == "PARTS_SHOP" and shop.is_empty():
			shop = h.data
		elif h.data.kind == "IMPOUND" and pound.is_empty():
			pound = h.data
		elif h.data.kind == "PRACTICE" and track.is_empty():
			track = h.data
		elif h.data.kind == "GARAGE" and garage.is_empty():
			garage = h.data

	for probe in [[dealer, "cars"], [shop, "parts"], [pound, "impound"],
			[track, "track"], [garage, "home"]]:
		var loc: Dictionary = probe[0]
		var noun: String = probe[1]
		var kind: String = loc.kind
		var cfg: Dictionary = LocationModal.KINDS[kind]

		map._on_hotspot_pressed(loc)
		await get_tree().process_frame

		_check("%s opens the panel" % kind.to_lower(), map._modal.visible)

		# The source PNGs are opaque black around the panel, which rendered as
		# a slab over the map. Each must be drawn cropped, and keyed at the
		# corners.
		# The panel also draws preview thumbnails, so the backdrop is picked by
		# its crop rather than by being the last TextureRect in the frame.
		var art: TextureRect = null
		for child in map._modal.frame.get_children():
			if child is TextureRect and child.texture is AtlasTexture \
					and (child.texture as AtlasTexture).region == cfg["crop"]:
				art = child
		_check("%s panel draws its own art" % noun,
			art != null and art.texture is AtlasTexture
				and (art.texture as AtlasTexture).atlas.resource_path == cfg["art"])
		_check("%s panel is cropped to the panel, not the canvas" % noun,
			art != null and (art.texture as AtlasTexture).region == cfg["crop"])
		_check("%s panel keys out its black corners" % noun,
			art != null and art.material is ShaderMaterial)

		# Keying on luminance across the whole panel faded a third of the
		# part shop, because these interiors are nearly black. The key must
		# stay confined to the corners.
		var mat: ShaderMaterial = art.material as ShaderMaterial
		_check("%s panel's key is confined to the corners" % noun,
			mat != null and mat.shader.code.contains("in_corner"))
		var reach: float = float(mat.get_shader_parameter("reach"))
		_check("%s panel's key reaches into the corners only" % noun,
			reach > 0.0 and reach < 0.5, str(reach))
		_check("%s panel's cut sits below its own interior" % noun,
			float(mat.get_shader_parameter("cut_high")) <= 0.012,
			str(mat.get_shader_parameter("cut_high")))

		if loc.hood != "":
			_check("%s panel names the district" % noun,
				map._modal._location_label.text
					== str(Catalog.get_neighborhood(loc.hood).get("name", "")).to_upper(),
				map._modal._location_label.text)

		if noun == "home":
			# Home reports the player's own garage, and its third cell is a
			# name rather than a number.
			_check("home panel counts the cars you own",
				map._modal._count_label.text == str(GameState.garage.size()),
				map._modal._count_label.text)
			_check("home panel shows your parking limit, not a price",
				map._modal._price_label.text.contains(str(GameState.parking_limit())),
				map._modal._price_label.text)
			_check("home names your active ride", map._modal._refresh_label.text != "",
				map._modal._refresh_label.text)
			_check("home has no district, so it names your home",
				map._modal._location_label.text == "YOUR HOME",
				map._modal._location_label.text)

			# With an active car chosen, its name should appear.
			var before_h: int = GameState.garage.size()
			var prev_active: String = GameState.active_car_id
			GameState.garage.append({"id": "ride_x", "nickname": "Vortex X1"})
			GameState.active_car_id = "ride_x"
			map._on_hotspot_pressed(loc)
			await get_tree().process_frame
			_check("the active ride is named, in caps as the artwork sets it",
				map._modal._refresh_label.text == "VORTEX X1",
				map._modal._refresh_label.text)
			GameState.garage.resize(before_h)
			GameState.active_car_id = prev_active
		elif noun == "track":
			# The track's cells mean different things again: how many event
			# types exist, what a run costs, and the player's quickest pass.
			_check("track panel reports the one event the game has",
				map._modal._count_label.text == "1", map._modal._count_label.text)
			_check("track panel says practice is free, not a price band",
				map._modal._price_label.text.contains("FREE"),
				map._modal._price_label.text)
			_check("track panel shows a best time in place of a refresh timer",
				map._modal._refresh_label.text == "--",
				map._modal._refresh_label.text)
			_check("track is ungated but still names the district it sits in",
				loc.hood == "" and map._modal._location_label.text == "WESTBAY",
				map._modal._location_label.text)

			# Record a pass and the best time should appear.
			var before_g: int = GameState.garage.size()
			GameState.garage.append({"id": "quick", "best_et": 9.92})
			map._on_hotspot_pressed(loc)
			await get_tree().process_frame
			_check("a recorded pass shows as the best time",
				map._modal._refresh_label.text == "9.92",
				map._modal._refresh_label.text)
			GameState.garage.resize(before_g)
		elif noun == "impound":
			# The impound reports the player's own seized cars and what it
			# would cost to get them out, not anything from the catalog.
			var held := 0
			for car in GameState.garage:
				if car.get("impounded", false):
					held += 1
			_check("impound panel counts the player's seized cars",
				map._modal._count_label.text == str(held),
				"%s vs %d" % [map._modal._count_label.text, held])
			_check("impound panel shows a release fee, not a price band",
				map._modal._price_label.text.contains("$")
					and not map._modal._price_label.text.contains("$$"),
				map._modal._price_label.text)

			# With nothing seized the fee is zero, which proves little, so the
			# test seizes two of its own rather than depending on the garage
			# happening to hold any.
			var before: int = GameState.garage.size()
			GameState.garage.append({"id": "seized_a", "impounded": true})
			GameState.garage.append({"id": "seized_b", "impounded": true})

			map._on_hotspot_pressed(loc)
			await get_tree().process_frame

			var fee: int = 2 * int(Catalog.impound_config().get("feePerCar", 0))
			_check("seizing cars updates the count",
				map._modal._count_label.text == "2", map._modal._count_label.text)
			_check("the fee is per car, times the number held",
				map._modal._price_label.text.contains(Design.fmt_cash(fee)),
				"%s should contain %s" % [map._modal._price_label.text, Design.fmt_cash(fee)])

			GameState.garage.resize(before)
			_check("impound has no district, so it names your home",
				map._modal._location_label.text == "YOUR HOME",
				map._modal._location_label.text)
		else:
			var stock: Array = Catalog.parts_in(loc.hood) if noun == "parts" \
				else Catalog.cars_in(loc.hood)
			_check("%s panel counts real stock, not the painted number" % noun,
				map._modal._count_label.text == str(stock.size()),
				"%s vs %d" % [map._modal._count_label.text, stock.size()])
			_check("%s panel shows a two-tone price band" % noun,
				map._modal._price_label.text.contains("$")
					and map._modal._price_label.text.to_upper().contains("F0A020"),
				map._modal._price_label.text)

		# This suite used to assert that every mask geometrically enclosed the
		# painted text, using bounds measured by brightness. Those fixtures
		# have been retired rather than repaired: the masks were since re-cut
		# to the ink by hue, deliberately narrower than the bright bounds,
		# because a full-row mask flattened the lit skyline behind the
		# location name into a black bar -- and the panel art has been
		# re-exported since they were taken. Re-measuring from outside picked
		# up the icons and panel chrome along with the glyphs, so the numbers
		# could not be re-derived honestly. Mask coverage now needs checking
		# by eye, and pinning again once it settles.

	_check("Harbour District shops accessible from Harbour District", GameState.can_shop_in("HARBOUR"))
	_check("Eastpoint locked from Harbour District", not GameState.can_shop_in("EASTPOINT"))

	# move_to() is a server transaction now, and this suite runs with no
	# server. What is under test here is the gating rule, not the move, so the
	# residence is set directly and can_shop_in is asked the question.
	GameState.player.cash = 100000
	GameState.player.neighborhood = "EASTPOINT"
	_check("Eastpoint unlocked once you live there",
		GameState.can_shop_in("EASTPOINT"))
	_check("Downtown still locked from Eastpoint",
		not GameState.can_shop_in("DOWNTOWN"))

	map.queue_free()


## The login screen is the only screen that renders before a session
## exists, so it must build with an empty GameState and no token.
func _test_auth_screen() -> void:
	print("\n-- auth screen")

	_check("AUTH is a routable screen",
		Router.SCENES.has(Router.Screen.AUTH))
	_check("auth scene file exists",
		ResourceLoader.exists(Router.SCENES[Router.Screen.AUTH]))

	var packed: PackedScene = load(Router.SCENES[Router.Screen.AUTH])
	var screen: Control = packed.instantiate()
	add_child(screen)
	await get_tree().process_frame

	var fields: Array = _find_all(screen, "LineEdit")
	var buttons: Array = _find_all(screen, "Button")

	_check("renders a racer name and password field", fields.size() == 2,
		"found %d" % fields.size())

	var secret_count := 0
	for f in fields:
		if f.secret:
			secret_count += 1
	_check("password field is masked", secret_count == 1,
		"%d masked" % secret_count)

	# The artwork draws the buttons; these are transparent hit areas placed
	# over them, so they carry no text of their own.
	_check("places a hit area over each painted control", buttons.size() == 7,
		"found %d" % buttons.size())

	var unlabelled := 0
	for b in buttons:
		if b.text == "":
			unlabelled += 1
	_check("hit areas draw no text over the art", unlabelled == buttons.size())

	_check("START is wired", screen._hit_start.pressed.get_connections().size() > 0)
	_check("LOGIN is wired", screen._hit_login.pressed.get_connections().size() > 0)
	_check("CREATE ACCOUNT is wired", screen._hit_create.pressed.get_connections().size() > 0)

	var was_secret: bool = screen._pass_field.secret
	screen._on_reveal()
	_check("the painted eye toggles password masking",
		screen._pass_field.secret != was_secret)
	screen._on_reveal()

	_check("errors stay hidden until there is one",
		not screen.notice.visible and screen.notice_label.text == "")

	screen.queue_free()
	await get_tree().process_frame

	# ── sign-up ───────────────────────────────────────────────
	print("\n-- signup screen")

	_check("SIGNUP is a routable screen",
		Router.SCENES.has(Router.Screen.SIGNUP))
	_check("signup scene file exists",
		ResourceLoader.exists(Router.SCENES[Router.Screen.SIGNUP]))
	_check("signup art is present",
		ResourceLoader.exists("res://assets/ui/signup.png"))

	var su_packed: PackedScene = load(Router.SCENES[Router.Screen.SIGNUP])
	var su: Control = su_packed.instantiate()
	add_child(su)
	await get_tree().process_frame

	var su_fields: Array = _find_all(su, "LineEdit")
	_check("asks for name, email, password and confirmation",
		su_fields.size() == 4, "found %d" % su_fields.size())

	var su_secret := 0
	for f in su_fields:
		if f.secret:
			su_secret += 1
	_check("both password fields are masked", su_secret == 2, "%d masked" % su_secret)

	_check("mismatched passwords are refused",
		su._validate("racer", "a@b.com", "hunter2hunter2", "hunter2hunter3")
			.contains("do not match"))
	_check("short passwords are refused",
		su._validate("racer", "a@b.com", "short", "short").contains("8 characters"))
	_check("a malformed email is refused",
		su._validate("racer", "not-an-email", "hunter2hunter2", "hunter2hunter2")
			.contains("email"))
	_check("a valid form passes validation",
		su._validate("racer", "a@b.com", "hunter2hunter2", "hunter2hunter2") == "")

	su.queue_free()
	await get_tree().process_frame
	return

	_check("login art is present",
		ResourceLoader.exists("res://assets/ui/screen.png"))


## Depth-first search for every node of a given class.
func _find_all(node: Node, klass: String) -> Array:
	var found: Array = []
	if node.is_class(klass):
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_all(child, klass))
	return found


## The header art has sample values painted into it. Every one must be
## covered and redrawn from GameState, or players see someone else's money.
func _test_header() -> void:
	print("\n-- game frame")

	_check("frame art is present",
		ResourceLoader.exists("res://assets/ui/citymap.png"))

	var bar := Control.new()
	bar.set_script(load("res://scripts/ui/GameFrame.gd"))
	add_child(bar)
	await get_tree().process_frame

	GameState.player["cash"] = 1234567
	GameState.player["street_credit"] = 35670
	GameState.player["rank"] = "Contender"
	bar.refresh()

	_check("cash comes from the player, not the artwork",
		bar._cash_label.text.contains("1,234,567"), bar._cash_label.text)
	_check("cash is not the painted sample",
		not bar._cash_label.text.contains("1,248,750"), bar._cash_label.text)
	_check("street credit is grouped and live",
		bar._credit_label.text == "35,670", bar._credit_label.text)
	_check("rank fills the driver badge",
		bar._level_label.text == "CONTENDER", bar._level_label.text)

	GameState.player["cash"] = 250
	bar.refresh()
	_check("cash follows the player changing", bar._cash_label.text.contains("250"),
		bar._cash_label.text)

	bar.set_screen_name("PARTS_SHOP")
	_check("the bar names the current screen",
		bar._screen_label.text == "PARTS SHOP", bar._screen_label.text)

	var hits: Array = _find_all(bar, "Button")
	_check("header and footer controls are clickable", hits.size() == 6,
		"found %d" % hits.size())

	bar.set_footer("LOCATIONS UNLOCKED", "3 / 11")
	_check("footer readout is live, not the painted sample",
		bar._count_label.text == "3 / 11", bar._count_label.text)

	bar.queue_free()
	await get_tree().process_frame


## The root scene wires Main.gd to the frame by node path, and nothing else
## in this suite loads it -- so a scene and its script can drift apart and
## every other check still passes. This is the check that catches that.
func _test_main_scene() -> void:
	print("\n-- root scene")

	var path := "res://scenes/core/Main.tscn"
	_check("root scene exists", ResourceLoader.exists(path))

	var packed: PackedScene = load(path)
	var main: Control = packed.instantiate()
	add_child(main)
	await get_tree().process_frame

	_check("fullscreen host present for login and sign-up",
		main.get_node_or_null("Fullscreen") != null)
	_check("frame present for in-game screens",
		main.get_node_or_null("Frame") != null)

	var frame: Node = main.get_node_or_null("Frame")
	_check("the frame is the GameFrame, not a bare Control",
		frame != null and frame.has_method("set_screen_name"))
	_check("the frame exposes a content host for screens",
		frame != null and frame.get("content") != null)

	main.queue_free()
	await get_tree().process_frame


## Booting with no session must land on a VISIBLE login screen. Checking only
## that the node exists is not enough: it was once parented inside the frame
## and then the frame was hidden, which is a black window with a perfectly
## healthy scene tree behind it.
func _test_boot_is_visible() -> void:
	print("\n-- boot")

	Api.sign_out()

	var packed: PackedScene = load("res://scenes/core/Main.tscn")
	var main: Control = packed.instantiate()
	add_child(main)
	for _i in 4:
		await get_tree().process_frame

	var fullscreen: Node = main.get_node_or_null("Fullscreen")
	var frame: Node = main.get_node_or_null("Frame")

	_check("signed out, the router opens the login screen",
		Router.current() == Router.Screen.AUTH)
	_check("the login screen is hosted outside the game frame",
		fullscreen != null and fullscreen.get_child_count() == 1,
		"fullscreen has %d children" % (fullscreen.get_child_count() if fullscreen else -1))
	_check("the game frame is hidden before there is a session",
		frame != null and not frame.visible)

	var login: Control = null
	if fullscreen != null and fullscreen.get_child_count() > 0:
		login = fullscreen.get_child(0)
	_check("the login screen is actually visible, not just present",
		login != null and login.is_visible_in_tree())

	main.queue_free()
	await get_tree().process_frame


## The part shop is a backdrop for now -- the interface that stood on it was
## taken out. What still matters is that the art is confined to the frame's
## content area: COVERED overhangs by design, and without clipping it paints
## over the header, footer and edge glow instead of stopping at them.
func _test_parts_shop() -> void:
	print("\n-- part shop")

	_check("part shop backdrop is present",
		ResourceLoader.exists("res://assets/ui/partshop_back.png"))
	_check("PARTS_SHOP routes to the real screen",
		str(Router.SCENES[Router.Screen.PARTS_SHOP]).contains("PartsShop"))

	var packed: PackedScene = load(Router.SCENES[Router.Screen.PARTS_SHOP])
	var shop: Control = packed.instantiate()
	add_child(shop)
	await get_tree().process_frame

	_check("the screen clips, so the art cannot cross the frame's borders",
		shop.clip_contents)

	# Picked by its texture, not by being the last TextureRect on the screen --
	# the car in the bay is one too.
	var art: TextureRect = null
	for child in shop.get_children():
		if child is TextureRect and child.texture != null \
				and str(child.texture.resource_path).contains("partshop_back"):
			art = child
	_check("the backdrop is drawn", art != null)
	_check("it fills the frame without distorting the workshop",
		art != null and art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED,
		str(art.stretch_mode) if art else "")
	_check("and it is laid across the whole content area",
		art != null and art.anchor_right == 1.0 and art.anchor_bottom == 1.0)

	# The categories column, top-left, over the workshop.
	_check("sidebar art is present",
		ResourceLoader.exists("res://assets/ui/part_shop_side.png"))
	_check("the column is built", shop._side != null)
	# The column is fitted the way the dealership's is: full height of the
	# content area, width from its own aspect, aligned to the left. Nothing
	# about it is a guessed fraction of the screen.
	var fitter: AspectRatioContainer = null
	for child in shop.get_children():
		if child is AspectRatioContainer:
			fitter = child
	_check("the column is laid out by an aspect fitter", fitter != null)
	_check("it keeps the artwork's own proportions",
		fitter != null and absf(fitter.ratio - shop.SIDE_W / shop.SIDE_H) < 0.001,
		"%.4f" % fitter.ratio if fitter else "none")
	_check("it stands the full height, left aligned",
		fitter != null and fitter.stretch_mode == AspectRatioContainer.STRETCH_FIT
			and fitter.alignment_horizontal == AspectRatioContainer.ALIGNMENT_BEGIN)
	_check("the column is its child, not a hand-placed rect",
		shop._side != null and shop._side.get_parent() == fitter)

	var rows: Array = _find_all(shop._side, "Button") if shop._side else []
	_check("every painted row has a hit area", rows.size() == 9,
		"%d rows" % rows.size())

	# The artwork names categories this game does not have. Those rows must be
	# inert rather than wired to the wrong shelf.
	var live := 0
	var inert := 0
	for b in rows:
		if b.disabled:
			inert += 1
		else:
			live += 1
	_check("rows the game has no parts for are inert", inert == 2, "%d inert" % inert)
	_check("the rest are wired", live == 7, "%d live" % live)

	shop._on_row("TURBO")
	_check("choosing a row records the category", shop._category == "TURBO",
		shop._category)

	# The shelf along the bottom.
	_check("the shelf is built", shop._strip != null and shop._cards != null)
	_check("it is pinned to the bottom",
		shop._strip != null and is_equal_approx(shop._strip.anchor_bottom, 1.0),
		"bottom %.2f" % shop._strip.anchor_bottom if shop._strip else "none")
	_check("and it has a pager beside it", shop._pager != null)

	var cards: Array = shop._cards.get_children() if shop._cards else []
	_check("turbos are on the shelf", cards.size() > 0, "%d cards" % cards.size())
	_check("the shelf always holds a full page of slots",
		cards.size() == shop.CARDS_PER_PAGE, "%d slots" % cards.size())

	# The last page is usually short. Its cards must stay the width they are
	# on a full page rather than stretching to fill the shelf.
	shop._on_row("ALL")
	var page1: int = 0
	for c in shop._cards.get_children():
		if c is PanelContainer:
			page1 += 1
	shop._on_next_page()
	var page2 := 0
	var fillers := 0
	for c in shop._cards.get_children():
		if c is PanelContainer:
			page2 += 1
		else:
			fillers += 1
	_check("a short last page is padded out, not stretched",
		page2 < shop.CARDS_PER_PAGE and page2 + fillers == shop.CARDS_PER_PAGE,
		"%d cards + %d fillers" % [page2, fillers])
	shop._page = 0
	shop._on_row("TURBO")

	# Which categories have a render and which do not. The uncovered ones draw
	# a card with no picture rather than borrowing another category's, so this
	# records the gap instead of hiding it.
	var missing: Array = []
	for cat in Catalog.part_categories():
		var path: String = str(shop.MODULE_ART.get(cat, ""))
		if path == "" or not ResourceLoader.exists(path):
			missing.append(cat)
	_check("every mapped category resolves to a file",
		shop.MODULE_ART.size() == 6 and missing.size() == 3,
		"missing: %s" % str(missing))
	_check("INTAKE and EXHAUST are the gap that matters",
		missing.has("INTAKE") and missing.has("EXHAUST"),
		"missing: %s" % str(missing))

	# ALL PARTS should read as a spread, not five of the same thing.
	shop._on_row("ALL")
	var kinds := {}
	for part in shop._stock():
		kinds[str(part.category)] = true
	_check("ALL PARTS shows one of each kind", kinds.size() == shop._stock().size(),
		"%d kinds across %d entries" % [kinds.size(), shop._stock().size()])

	# Choosing a card marks it and leaves the rest alone.
	shop._on_row("TURBO")
	var first: Dictionary = shop._stock()[0]
	shop._on_card(str(first.id))
	_check("choosing a card selects it", shop._selected == str(first.id),
		shop._selected)

	# The player's own car, standing in the workshop.
	_check("the car view is built", shop._car != null)
	_check("with no car there is nothing to show",
		shop._car != null and not shop._car.visible,
		"garage holds %d, active is '%s'" % [GameState.garage.size(),
			GameState.active_car_id])

	GameState.garage = [{
		"id": "shop_car", "model_id": "cm_coupe_import", "nickname": "Test Mule",
		"installed": {}, "tune": {}, "condition": {},
	}]
	GameState.active_car_id = "shop_car"
	shop._refresh_car()
	await get_tree().process_frame

	_check("an active car appears in the bay",
		shop._car != null and shop._car.visible)
	# The bay shows the same photograph the showroom sells the car with, not
	# the procedural placeholder sprite -- one source for what a car looks
	# like, so the garage and the dealership cannot disagree.
	_check("it shows the showroom's photograph of that car",
		shop._car != null and shop._car.texture != null
			and str(shop._car.texture.resource_path).contains("assets/ui/cars"),
		str(shop._car.texture.resource_path) if shop._car and shop._car.texture else "none")
	_check("and it is the same one the catalog hands out",
		shop._car != null and shop._car.texture
			== Catalog.car_shot(Catalog.get_car_model("cm_coupe_import")))
	_check("the sprite is not distorted",
		shop._car != null
			and shop._car.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED)

	# Selling the last car has to empty the bay, not leave a ghost.
	GameState.garage = []
	GameState.active_car_id = ""
	shop._refresh_car()
	_check("selling the last car empties the bay",
		shop._car != null and not shop._car.visible)

	# The part details panel. The artwork is a template with empty slots, so
	# what matters is that every slot gets filled and the maths is right.
	_check("part details art is present",
		ResourceLoader.exists("res://assets/ui/part_shop_modal.png"))
	_check("the panel is built", shop._details != null)
	# Checked on a fresh panel: the card tests above have already opened the
	# screen's own one, so asking it now would prove nothing.
	var fresh := PartDetailsPanel.new()
	add_child(fresh)
	await get_tree().process_frame
	_check("a panel starts hidden until a part is chosen", not fresh.visible)
	fresh.queue_free()

	var turbo := Catalog.get_part("pt_turbo_t3")
	shop._details.show_part(turbo, {}, "res://assets/ui/modules/turbo.png")
	_check("choosing a part shows the panel", shop._details.visible)
	_check("it names the part", shop._details._name.text == "TWIN SCROLL TURBO",
		shop._details._name.text)
	_check("with its tier and category",
		shop._details._badge.text.contains("TIER 3")
			and shop._details._badge.text.contains("TURBO"),
		shop._details._badge.text)
	_check("and where it is sold",
		shop._details._location.text.length() > 0, shop._details._location.text)
	_check("the price is filled in",
		shop._details._price.text.contains("15,000"), shop._details._price.text)
	_check("the product shot goes top right",
		shop._details._shot.visible and shop._details._shot.texture != null)

	# The table panel's top edge is at y=404 in the template. Anything in the
	# header that reaches past it gets cut in half, which is what happened to
	# the summary line.
	var panel: PartDetailsPanel = shop._details
	for slot in [["name", panel.R_NAME], ["badge", panel.R_BADGE],
			["location", panel.R_LOCATION], ["summary", panel.R_SUMMARY],
			["shot", panel.R_SHOT]]:
		var r: Rect2 = slot[1]
		_check("the %s stops above the table" % slot[0],
			r.position.y + r.size.y <= panel.HEADER_BOTTOM,
			"ends at %d, table starts at %d" % [r.position.y + r.size.y,
				panel.HEADER_BOTTOM])

	# The text column and the picture must not sit on top of each other.
	_check("the shot clears the text beside it",
		panel.R_SHOT.position.x >= panel.R_NAME.position.x + panel.R_NAME.size.x,
		"shot at %d, text ends at %d" % [panel.R_SHOT.position.x,
			panel.R_NAME.position.x + panel.R_NAME.size.x])

	# No car means no baseline, so the columns must say so rather than show a
	# made-up before figure.
	_check("with no car the columns are blank",
		shop._details._cells[0].before.text == "—",
		shop._details._cells[0].before.text)

	# A real preview: power up, weight up, gears unchanged.
	shop._details.show_part(turbo, {
		"before": {"peakHp": 106, "peakTorque": 99, "totalWeight": 2050},
		"after": {"peakHp": 215, "peakTorque": 339, "totalWeight": 2120},
		"redline": 7200, "gearCount": 5,
	}, "")
	_check("power shows before, after and the gain",
		shop._details._cells[0].before.text == "106 HP"
			and shop._details._cells[0].after.text == "215 HP"
			and shop._details._cells[0].delta.text == "+109 HP",
		"%s / %s / %s" % [shop._details._cells[0].before.text,
			shop._details._cells[0].after.text, shop._details._cells[0].delta.text])
	_check("a gain is coloured as good",
		shop._details._cells[0].delta.get_theme_color("font_color") == Design.GOOD)

	# Weight is the row where up is bad.
	_check("added weight is coloured as a cost",
		shop._details._cells[2].delta.text == "+70 LB"
			and shop._details._cells[2].delta.get_theme_color("font_color") == Design.BAD,
		shop._details._cells[2].delta.text)

	# Nothing in this game changes redline or gear count.
	_check("unchanged rows show a dash, not a zero",
		shop._details._cells[4].delta.text == "—",
		shop._details._cells[4].delta.text)
	_check("and still show the real figures",
		shop._details._cells[3].before.text == "7200 RPM"
			and shop._details._cells[4].after.text == "5",
		"%s / %s" % [shop._details._cells[3].before.text,
			shop._details._cells[4].after.text])

	shop.queue_free()
	await get_tree().process_frame


## The garage is a backdrop for now. What matters is the same thing as the
## part shop: the art is confined to the frame's content area, because COVERED
## overhangs by design and without clipping it paints over the borders.
func _test_garage() -> void:
	print("\n-- garage")

	_check("garage backdrop is present",
		ResourceLoader.exists("res://assets/ui/garage_background.png"))
	_check("GARAGE routes to the real screen, not the stub",
		str(Router.SCENES[Router.Screen.GARAGE]).contains("Garage"))

	var packed: PackedScene = load(Router.SCENES[Router.Screen.GARAGE])
	var garage: Control = packed.instantiate()
	add_child(garage)
	await get_tree().process_frame

	_check("it is no longer the placeholder",
		garage.get_script() != null
			and str(garage.get_script().resource_path).contains("GarageScreen"),
		str(garage.get_script().resource_path) if garage.get_script() else "none")
	_check("the screen clips, so the art cannot cross the frame's borders",
		garage.clip_contents)

	var art: TextureRect = null
	for child in garage.get_children():
		if child is TextureRect and child.texture != null \
				and str(child.texture.resource_path).contains("garage_background"):
			art = child
	_check("the backdrop is drawn", art != null)
	_check("it fills the frame without distorting the garage",
		art != null and art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	_check("and it is laid across the whole content area",
		art != null and art.anchor_right == 1.0 and art.anchor_bottom == 1.0)

	# The sidebar: an empty frame in the artwork, so the whole list is built
	# here and has to land inside the opening.
	_check("garage sidebar art is present",
		ResourceLoader.exists("res://assets/ui/garage_side.png"))
	_check("the column is built", garage._side != null)

	var fitter: AspectRatioContainer = null
	for child in garage.get_children():
		if child is AspectRatioContainer:
			fitter = child
	_check("it is laid out by an aspect fitter, like the other columns",
		fitter != null and absf(fitter.ratio - garage.SIDE_W / garage.SIDE_H) < 0.001)

	# The artwork carries transparent padding before its visible frame. Laid
	# flush, the panel floats off the border by exactly that much, so the
	# column is pulled out by it and only empty pixels are clipped.
	# The artwork carries transparent padding, so fitting the file leaves the
	# panel short and off the border. The frame inside it is fitted instead.
	_check("the visible frame is smaller than its file",
		garage.FRAME.size.x < garage.SIDE_W and garage.FRAME.size.y < garage.SIDE_H,
		str(garage.FRAME))
	garage._place_stage()
	_check("the file hangs left of the content area by its own padding",
		fitter != null and fitter.offset_left < 0.0,
		"left %.1f" % fitter.offset_left if fitter else "none")

	# The invariant that matters, and the one a nudge cannot break: the box
	# the artwork is fitted into is taller than the content area by exactly
	# the file's vertical padding, so the frame inside it fills the content.
	if fitter != null and garage.size.y > 0.0:
		var k: float = garage.size.y / garage.FRAME.size.y
		var box_h: float = garage.size.y - fitter.offset_top + fitter.offset_bottom
		_check("and is scaled so its visible frame fills the height",
			absf(box_h - garage.SIDE_H * k) < 1.0,
			"box %.1f vs %.1f" % [box_h, garage.SIDE_H * k])

	# Everything must sit inside the frame's measured opening.
	var open_rect: Rect2 = garage.OPENING
	# The frame has a decorative hairline inside its border. Content laid on
	# that line gets cut by it, which is what happened to the heading.
	_check("content starts inside the frame's border",
		garage.OPENING.position.y >= garage.FRAME.position.y + 40,
		str(garage.OPENING.position.y))
	_check("the heading has room to breathe",
		garage.HEADER_H >= 90, str(garage.HEADER_H))

	# The frame's interior, re-measured after the artwork was narrowed: the
	# border's inner face is at x=132 and x=892, y=70 and y=1440.
	# The border's inner face, re-measured after the artwork changed size.
	_check("the opening is inside the border",
		open_rect.position.x >= 177 and open_rect.position.y >= 74
			and open_rect.position.x + open_rect.size.x <= 771
			and open_rect.position.y + open_rect.size.y <= 1545,
		str(open_rect))

	# With no cars it says so rather than showing an empty frame.
	GameState.garage = []
	GameState.active_car_id = ""
	garage._rebuild()
	await get_tree().process_frame
	var text := ""
	for l in _find_all(garage, "Label"):
		text += l.text + " "
	_check("an empty garage explains itself",
		text.to_lower().contains("nothing parked"), text.substr(0, 80))

	# Three cars, one of them active, one seized.
	GameState.garage = [
		{"id": "c1", "model_id": "cm_hatch_kei", "nickname": "Runabout", "impounded": false},
		{"id": "c2", "model_id": "cm_muscle_classic", "nickname": "Brawler", "impounded": false},
		{"id": "c3", "model_id": "cm_sport_rwd", "nickname": "Seized One", "impounded": true},
	]
	GameState.active_car_id = "c1"
	garage._rebuild()
	await get_tree().process_frame

	# A card is a Control with a Panel behind it -- not a PanelContainer,
	# which would stretch the badge across the whole card.
	var cards := 0
	for c in garage._list.get_children():
		for inner in c.get_children():
			if inner is Panel:
				cards += 1
				break
	_check("every car gets a card", cards == 3, "%d cards" % cards)
	_check("cards are not PanelContainers, so the badge stays in its corner",
		not (garage._list.get_child(0) is PanelContainer))
	_check("the count reads owned against the parking limit",
		garage._count.text == "3 / %d" % GameState.parking_limit(),
		garage._count.text)

	var labels := ""
	for l in _find_all(garage._list, "Label"):
		labels += l.text + " "
	# One source for car photographs: the garage must show what the showroom
	# shows, not the flat placeholder sprite.
	var card_shots := 0
	for t in _find_all(garage._list, "TextureRect"):
		if t.texture != null and str(t.texture.resource_path).contains("assets/ui/cars"):
			card_shots += 1
	_check("cards use the showroom photographs", card_shots == 3,
		"%d of 3 cards have one" % card_shots)

	# The badge grew past its offset box at panel scale, and a Control expands
	# rightward by default -- which walked it into the middle of the card.
	# Growing from the END keeps any expansion leftward, off the right anchor.
	var chip_found := false
	for c in garage._list.get_children():
		for inner in c.get_children():
			if inner is Label and inner.text == "ACTIVE":
				chip_found = true
				_check("the ACTIVE chip grows leftward from the corner",
					inner.grow_horizontal == Control.GROW_DIRECTION_BEGIN
						and inner.anchor_left == 1.0)
	_check("the active card carries its chip", chip_found)

	_check("cards name the car and its class",
		labels.contains("RUNABOUT") and labels.contains("MUSCLE CLASS"), labels.substr(0, 90))
	_check("the car you drive is badged ACTIVE", labels.contains("ACTIVE"))
	_check("and a seized car says so", labels.contains("IMPOUNDED"))

	# Clicking a card looks at that car; driving it is a second step, so a
	# misclick in the list cannot change which car a race would use.
	_check("the active car is what you start out looking at",
		garage._selected == "c1", garage._selected)
	_check("the floor shows it", garage._hero.visible and garage._hero.texture != null)

	garage._on_car("c2", false)
	await get_tree().process_frame
	_check("clicking another car looks at it", garage._selected == "c2",
		garage._selected)
	_check("without changing what you drive", GameState.active_car_id == "c1",
		GameState.active_car_id)
	_check("the floor shows that car's photograph",
		garage._hero.texture == Catalog.car_shot(Catalog.get_car_model("cm_muscle_classic")))

	# Selling whatever you were looking at must not leave a blank floor.
	garage._selected = "gone"
	garage._refresh_stage()
	_check("a selection that no longer exists falls back to the active car",
		garage._selected == GameState.active_car_id, garage._selected)

	garage._selected = "c1"
	garage._rebuild()
	await get_tree().process_frame

	# Sorting cycles rather than needing a menu.
	var before_sort: String = garage.SORTS[garage._sort]
	garage._on_sort()
	_check("the sort control cycles",
		garage.SORTS[garage._sort] != before_sort,
		"%s -> %s" % [before_sort, garage.SORTS[garage._sort]])
	_check("and the control says what it is sorted by",
		garage._sort_button.text.contains(garage.SORTS[garage._sort]),
		garage._sort_button.text)
	_check("with a chevron, so it reads as a control",
		garage._sort_button.text.contains("▾"), garage._sort_button.text)
	# The frame around it is angular, so a square-cornered box looked pasted
	# on. It sits on a drawn plate with cut corners instead.
	_check("the sort control sits on a chamfered plate",
		garage._sort_plate is AngularPlate)
	_check("with its corners actually cut", garage._sort_plate.cut > 0.0,
		str(garage._sort_plate.cut))
	_check("and the plate is darker than the panel it sits in",
		garage._sort_plate.fill.get_luminance() < Design.BG_PANEL.get_luminance(),
		str(garage._sort_plate.fill))
	_check("the button draws no box of its own over it",
		garage._sort_button.get_theme_stylebox("normal") is StyleBoxEmpty)

	# Hover lights the plate rather than washing its fill.
	var rest: Color = garage._sort_plate.edge
	garage._on_sort_hover(true)
	_check("hover lights the plate's edge", garage._sort_plate.edge != rest)
	garage._on_sort_hover(false)

	# The car is kept to the left, so the right of the floor stays free.
	_check("the car leaves the right of the floor clear",
		garage.HERO_RIGHT < 0.75, str(garage.HERO_RIGHT))
	garage._place_stage()
	_check("and is laid out that way",
		absf(garage._hero.anchor_right - garage.HERO_RIGHT) < 0.001,
		str(garage._hero.anchor_right))

	GameState.garage = []
	GameState.active_car_id = ""

	# The car panel on the right. The artwork is a template with empty slots,
	# so what matters is that they get filled from the server's numbers.
	_check("garage panel art is present",
		ResourceLoader.exists("res://assets/ui/garage_func.png"))
	_check("the panel is built", garage._panel is GarageFuncPanel)

	GameState.garage = [
		{"id": "c1", "model_id": "cm_hatch_kei", "nickname": "Runabout", "impounded": false},
		{"id": "c2", "model_id": "cm_muscle_classic", "nickname": "Brawler", "impounded": false},
	]
	GameState.active_car_id = "c1"
	garage._selected = "c1"
	garage._panel.show_car(GameState.get_car("c1"), {
		"peakHp": 106, "peakTorque": 99, "totalWeight": 2050, "grip": 1.0,
	})
	await get_tree().process_frame

	_check("the panel shows a car", garage._panel.visible)
	_check("power, torque and weight are filled from the server",
		garage._panel._values[0].text == "106 HP"
			and garage._panel._values[1].text == "99 LB-FT"
			and garage._panel._values[2].text == "2050 LB",
		"%s / %s / %s" % [garage._panel._values[0].text,
			garage._panel._values[1].text, garage._panel._values[2].text])
	_check("handling reads the grip the server now reports",
		garage._panel._values[5].text == "1", garage._panel._values[5].text)

	# Two rows have no answer in this game yet, and must say so rather than
	# showing a number nobody measured.
	_check("top speed and acceleration are left blank, not invented",
		garage._panel._values[3].text == "—" and garage._panel._values[4].text == "—",
		"%s / %s" % [garage._panel._values[3].text, garage._panel._values[4].text])

	# With no server answer yet, the panel reads the catalog the way the
	# dealership plate does, so it is never blank while a request is in
	# flight -- or failing.
	garage._panel.show_car(GameState.get_car("c1"), {})
	_check("without server stats the model's base figures stand in",
		garage._panel._values[0].text == "105 HP"
			and garage._panel._values[2].text == "2050 LB",
		"%s / %s" % [garage._panel._values[0].text, garage._panel._values[2].text])
	_check("including a stock grip for handling",
		garage._panel._values[5].text != "—", garage._panel._values[5].text)
	garage._panel.show_car(GameState.get_car("c1"), {
		"peakHp": 106, "peakTorque": 99, "totalWeight": 2050, "grip": 1.0,
	})

	_check("owned and slots come from the garage",
		garage._panel._owned.text == "2"
			and garage._panel._slots.text == str(GameState.parking_limit()),
		"%s / %s" % [garage._panel._owned.text, garage._panel._slots.text])
	# The artwork leaves its whole header empty; the car's identity goes there.
	_check("the panel names the car", garage._panel._name.text == "RUNABOUT",
		garage._panel._name.text)
	_check("and gives its class", garage._panel._class.text == "IMPORT CLASS",
		garage._panel._class.text)
	_check("the square top right is the tier badge",
		garage._panel._tier.text.length() == 1, garage._panel._tier.text)
	# Tier is banded off price, so a cheap car and an expensive one differ.
	_check("tier follows what the car costs",
		garage._panel._tier_for(Catalog.get_car_model("cm_hatch_kei"))
			!= garage._panel._tier_for(Catalog.get_car_model("cm_exotic_hyper")),
		"%s vs %s" % [garage._panel._tier_for(Catalog.get_car_model("cm_hatch_kei")),
			garage._panel._tier_for(Catalog.get_car_model("cm_exotic_hyper"))])

	# The file is fully opaque, so without a key it lands as a black slab.
	var panel_art: TextureRect = null
	for child in garage._panel.frame.get_children():
		if child is TextureRect and child.texture != null \
				and str(child.texture.resource_path).contains("garage_func"):
			panel_art = child
	_check("the panel's black corners are keyed out",
		panel_art != null and panel_art.material is ShaderMaterial)
	_check("and the key is confined to the corners, not the whole face",
		panel_art != null
			and (panel_art.material as ShaderMaterial).shader.code.contains("in_corner"))

	# The preview strip is the rest of the garage, this car first.
	var shown := 0
	for img in garage._panel._previews:
		if img.visible:
			shown += 1
	_check("the preview strip shows the cars you own", shown == 2,
		"%d of 5 slots filled" % shown)

	# The car you already drive cannot be set active again.
	_check("set active is off for the car you already drive",
		garage._panel._set_active.disabled)
	garage._panel.show_car(GameState.get_car("c2"), {})
	_check("and on for one you do not", not garage._panel._set_active.disabled)

	GameState.garage = []
	GameState.active_car_id = ""

	garage.queue_free()
	await get_tree().process_frame


## JSON null is not a missing key. Dictionary.get()'s default only fires when
## the key is absent, so str() on a null field yields the text "<null>" --
## which is truthy, non-empty, and silently wrong everywhere it is used.
func _test_null_fields() -> void:
	print("\n-- null handling")

	GameState._apply_player({
		"id": "p1", "username": "racer", "cash": 500, "neighborhood": "HARBOUR",
		"streetCredit": 0, "rank": "Noob", "totalRaces": 0, "wins": 0,
		"activeCarId": null,
	})
	_check("a null active car reads as no active car",
		GameState.active_car_id == "", GameState.active_car_id)

	var car := GameState._car_from_server({
		"id": "c1", "modelId": "cm_hatch_kei", "nickname": "Test", "plate": "AAA",
		"paintColor": null, "intakeId": null, "turboId": null, "bestEt": null,
	})
	_check("a null paint colour falls back rather than reading '<null>'",
		car.paint_color == "#1A1A1A", car.paint_color)
	_check("empty part slots are empty, not '<null>'",
		car.installed.intake == "" and car.installed.turbo == "",
		"%s / %s" % [car.installed.intake, car.installed.turbo])

	GameState.reset()


func _report() -> void:
	print("\n" + "=".repeat(48))
	print("  %d passed, %d failed" % [_pass, _fail])
	if _fail > 0:
		print("\n  Failures:")
		for f in _failures:
			print("    - %s" % f)
	print("=".repeat(48) + "\n")
	get_tree().quit(1 if _fail > 0 else 0)
