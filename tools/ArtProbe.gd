extends Node
## Measures the painted value text on each location panel, matching ink by
## hue rather than brightness.
##
## Brightness alone is wrong here: the location name sits on a lit skyline
## photo, so a brightness threshold returns the photo's bounds, not the
## name's. Matching the panel's own ink colour finds the glyphs and nothing
## else -- which is how the masks in LocationModal are cut.

const KINDS := [
	{ "name": "DEALERSHIP", "art": "res://assets/ui/dealership.png", "ink": Color("#31CDF7"),
	  "cells": [Rect2i(170, 430, 380, 120), Rect2i(200, 650, 200, 110),
				Rect2i(420, 650, 300, 110), Rect2i(700, 640, 280, 120)] },
	{ "name": "PARTS_SHOP", "art": "res://assets/ui/partshop.png", "ink": Color("#FF9B03"),
	  "cells": [Rect2i(170, 440, 400, 120), Rect2i(200, 680, 210, 110),
				Rect2i(430, 680, 320, 110), Rect2i(700, 670, 300, 120)] },
	{ "name": "IMPOUND", "art": "res://assets/ui/impound.png", "ink": Color("#FF3C37"),
	  "cells": [Rect2i(190, 430, 400, 120), Rect2i(220, 670, 200, 110),
				Rect2i(450, 660, 320, 110), Rect2i(750, 660, 290, 120)] },
	{ "name": "PRACTICE", "art": "res://assets/ui/racestack.png", "ink": Color("#FFBA0B"),
	  "cells": [Rect2i(160, 380, 400, 110), Rect2i(200, 740, 200, 110),
				Rect2i(440, 740, 300, 110), Rect2i(680, 740, 320, 110)] },
	{ "name": "GARAGE", "art": "res://assets/ui/home.png", "ink": Color("#FF9D05"),
	  "cells": [Rect2i(180, 340, 400, 110), Rect2i(220, 750, 200, 110),
				Rect2i(460, 750, 220, 110), Rect2i(700, 740, 300, 120)] },
]

const LABELS := ["location", "count", "price", "refresh"]

## How close a pixel's hue must be to the panel's ink, in degrees.
const HUE_TOLERANCE := 26.0
const MIN_SAT := 0.45
const MIN_VAL := 0.35


func _ready() -> void:
	for kind in KINDS:
		var art_path: String = kind["art"]
		if not ResourceLoader.exists(art_path):
			print("%s: missing %s" % [kind["name"], art_path])
			continue

		var img: Image = (load(art_path) as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)

		var ink: Color = kind["ink"]
		print("\n%s  (%dx%d)" % [kind["name"], img.get_width(), img.get_height()])

		var cells: Array = kind["cells"]
		for i in cells.size():
			var box: Rect2i = cells[i]
			var r := _ink_bounds(img, box, ink)
			if r == Rect2i():
				print("  %-9s  no ink found in %s" % [LABELS[i], box])
				continue
			print('  "%s": Rect2(%d, %d, %d, %d),'
				% [LABELS[i], r.position.x, r.position.y, r.size.x, r.size.y])
	print("")
	get_tree().quit()


func _ink_bounds(img: Image, box: Rect2i, ink: Color) -> Rect2i:
	var target := ink.h * 360.0
	var min_x := box.position.x + box.size.x
	var max_x := box.position.x - 1
	var min_y := box.position.y + box.size.y
	var max_y := box.position.y - 1

	for y in range(box.position.y, box.position.y + box.size.y):
		if y < 0 or y >= img.get_height():
			continue
		for x in range(box.position.x, box.position.x + box.size.x):
			if x < 0 or x >= img.get_width():
				continue
			var c := img.get_pixel(x, y)
			if c.s < MIN_SAT or c.v < MIN_VAL:
				continue
			var diff: float = absf(c.h * 360.0 - target)
			diff = minf(diff, 360.0 - diff)
			if diff > HUE_TOLERANCE:
				continue
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			min_y = mini(min_y, y)
			max_y = maxi(max_y, y)

	if max_x < min_x:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
