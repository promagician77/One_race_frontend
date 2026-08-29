extends Node
## Measures where the location badges actually sit in citymap.png, so the
## LOCATIONS table is measured rather than estimated off a screenshot.
##
##   godot --headless --path client tools/PinScan.tscn
##
## Blind blob detection does not work here: the badges are thin rings, and at
## any useful scan resolution the blue ones fragment. Instead each pin's
## current position is used as a seed and snapped to the centroid of the
## coloured pixels around it, which is robust to a broken ring.

const ART := "res://assets/ui/citymap.png"

## The map interior, matching GameFrame.CONTENT.
const AREA := Rect2i(28, 108, 1616, 740)

## Half-width of the search window, in source pixels. Wide enough to hold a
## badge, tight enough to exclude the caption printed beneath it.
const WINDOW := 30

## Seeds: the table as it stands today.
const SEEDS := [
	["shop_northridge",   0.235, 0.151],
	["impound",           0.335, 0.082],
	["dealer_northridge", 0.527, 0.111],
	["dealer_eastpoint",  0.754, 0.168],
	["dealer_westbay",    0.113, 0.351],
	["track",             0.337, 0.435],
	["dealer_downtown",   0.624, 0.427],
	["shop_eastpoint",    0.848, 0.427],
	["shop_harbour",      0.713, 0.614],
	["home",              0.487, 0.728],
	["dealer_harbour",    0.186, 0.788],
]


func _ready() -> void:
	var tex: Texture2D = load(ART)
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)

	print("\n%-18s %-13s %-13s %-8s" % ["id", "was", "measured", "moved"])
	print("-".repeat(60))

	var lines: Array[String] = []
	for seed_row in SEEDS:
		var id: String = seed_row[0]
		var nx: float = seed_row[1]
		var ny: float = seed_row[2]

		var px: int = AREA.position.x + int(nx * float(AREA.size.x))
		var py: int = AREA.position.y + int(ny * float(AREA.size.y))

		var found := _centroid_near(img, px, py)
		if found == Vector2i(-1, -1):
			print("%-18s %-13s %-13s %s" % [id, "%.3f,%.3f" % [nx, ny], "--", "no pixels"])
			continue

		var new_nx: float = float(found.x - AREA.position.x) / float(AREA.size.x)
		var new_ny: float = float(found.y - AREA.position.y) / float(AREA.size.y)

		print("%-18s %-13s %-13s %d,%d px" % [
			id,
			"%.3f,%.3f" % [nx, ny],
			"%.3f,%.3f" % [new_nx, new_ny],
			found.x - px, found.y - py,
		])
		lines.append('\t{ "id": "%s", "pos": Vector2(%.3f, %.3f) },' % [id, new_nx, new_ny])

	print("\n--- measured positions ---")
	for line in lines:
		print(line)
	print("--- end ---\n")

	get_tree().quit()


## Centre of mass of the badge pixels around a seed.
##
## Badge strokes are either strongly coloured (orange, blue, red) or close to
## white (the race track). The map underneath is desaturated and mid-dark, so
## both tests exclude it.
func _centroid_near(img: Image, cx: int, cy: int) -> Vector2i:
	var sum_x := 0
	var sum_y := 0
	var count := 0

	for y in range(cy - WINDOW, cy + WINDOW + 1):
		if y < 0 or y >= img.get_height():
			continue
		for x in range(cx - WINDOW, cx + WINDOW + 1):
			if x < 0 or x >= img.get_width():
				continue
			var c := img.get_pixel(x, y)
			var coloured := c.s > 0.35 and c.v > 0.40
			var bright := c.s < 0.25 and c.v > 0.82
			if not (coloured or bright):
				continue
			sum_x += x
			sum_y += y
			count += 1

	if count < 40:
		return Vector2i(-1, -1)
	return Vector2i(sum_x / count, sum_y / count)
