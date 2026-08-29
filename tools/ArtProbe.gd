extends Node
## Finds the exact bounds and colour of text painted into a panel, so masks
## can be sized to cover it and replacement type can match it.

const ART := "res://assets/ui/partshop.png"

## Search boxes to inspect, in source-image pixels. Each should bracket one
## painted value with a little room around it.
const PROBES := []

## Single points sampled for flat background colour, so masks blend in.
const SAMPLES := [
	["count_above",  Vector2i(270, 700)],
	["count_below",  Vector2i(270, 762)],
	["count_right",  Vector2i(330, 730)],
	["price_above",  Vector2i(600, 696)],
	["price_below",  Vector2i(600, 764)],
	["refresh_above", Vector2i(830, 694)],
	["refresh_below", Vector2i(830, 764)],
	["loc_above",    Vector2i(300, 452)],
	["loc_below",    Vector2i(300, 540)],
]

const BRIGHT := 0.30   ## luminance above which a pixel counts as ink


func _ready() -> void:
	var img: Image = (load(ART) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)

	print("")
	for probe in PROBES:
		var label: String = probe[0]
		var box: Rect2i = probe[1]

		var min_x := box.position.x + box.size.x
		var max_x := box.position.x - 1
		var min_y := box.position.y + box.size.y
		var max_y := box.position.y - 1
		var r := 0.0
		var g := 0.0
		var b := 0.0
		var n := 0
		var best := Color.BLACK
		var best_lum := 0.0

		for y in range(box.position.y, box.position.y + box.size.y):
			for x in range(box.position.x, box.position.x + box.size.x):
				if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
					continue
				var c := img.get_pixel(x, y)
				if maxf(c.r, maxf(c.g, c.b)) < BRIGHT:
					continue
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
				r += c.r
				g += c.g
				b += c.b
				n += 1
				var lum := maxf(c.r, maxf(c.g, c.b))
				if lum > best_lum:
					best_lum = lum
					best = c

		if n == 0:
			print("%-10s  nothing above %.2f luminance" % [label, BRIGHT])
			continue

		print("%-10s  Rect2(%d, %d, %d, %d)   h=%d   mean=#%s   brightest=#%s" % [
			label, min_x, min_y, max_x - min_x + 1, max_y - min_y + 1,
			max_y - min_y + 1,
			Color(r / n, g / n, b / n).to_html(false), best.to_html(false),
		])
	# How much of the panel does the corner key actually eat? Anything inside
	# the smoothstep range is rendered semi-transparent.
	var crop := Rect2i(62, 50, 903, 1445)
	var below_high := 0
	var below_low := 0
	var total := 0
	for y in range(crop.position.y, crop.position.y + crop.size.y, 3):
		for x in range(crop.position.x, crop.position.x + crop.size.x, 3):
			var c := img.get_pixel(x, y)
			var lum := maxf(c.r, maxf(c.g, c.b))
			total += 1
			if lum < 0.022:
				below_high += 1
			if lum < 0.006:
				below_low += 1
	print("inside crop: %.1f%% below 0.022 (faded by the key), %.1f%% below 0.006"
		% [100.0 * below_high / total, 100.0 * below_low / total])

	for smp in SAMPLES:
		var pt: Vector2i = smp[1]
		var c := img.get_pixel(pt.x, pt.y)
		print("%-14s (%4d,%4d)  #%s" % [smp[0], pt.x, pt.y, c.to_html(false)])

	var w := img.get_width()
	var h := img.get_height()
	var cx1 := w
	var cx2 := -1
	var cy1 := h
	var cy2 := -1
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var c := img.get_pixel(x, y)
			if maxf(c.r, maxf(c.g, c.b)) <= 0.05:
				continue
			cx1 = mini(cx1, x)
			cx2 = maxi(cx2, x)
			cy1 = mini(cy1, y)
			cy2 = maxi(cy2, y)
	print("\ncontent box -> Rect2(%d, %d, %d, %d)   has_alpha=%s"
		% [cx1, cy1, cx2 - cx1 + 1, cy2 - cy1 + 1, img.detect_alpha()])
	print("")
	get_tree().quit()
