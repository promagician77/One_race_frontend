extends Node
## Does the garage panel have transparency, or is it an opaque black slab?

const ART := "res://assets/ui/garage_func.png"


func _ready() -> void:
	var img: Image = (load(ART) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)

	var w := img.get_width()
	var h := img.get_height()
	print("\n%dx%d  detect_alpha=%s" % [w, h, img.detect_alpha()])

	for p in [Vector2i(2, 2), Vector2i(w - 3, 2), Vector2i(2, h - 3),
			Vector2i(w - 3, h - 3), Vector2i(w / 2, 4), Vector2i(w / 2, h / 2)]:
		var c := img.get_pixel(p.x, p.y)
		print("  (%4d,%4d)  rgba %.2f %.2f %.2f a=%.2f  lum %.3f"
			% [p.x, p.y, c.r, c.g, c.b, c.a, maxf(c.r, maxf(c.g, c.b))])

	# How much of the file is near-black, and how much is transparent.
	var dark := 0
	var clear := 0
	var total := 0
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			var c := img.get_pixel(x, y)
			total += 1
			if c.a < 0.5:
				clear += 1
			if maxf(c.r, maxf(c.g, c.b)) < 0.03:
				dark += 1
	print("\n%.1f%% transparent, %.1f%% near-black" % [100.0 * clear / total, 100.0 * dark / total])

	print("\ntop area, where the name belongs -- brightness by row (cols 100..700):")
	for y in range(0, 230, 10):
		var sum := 0.0
		var n := 0
		for x in range(100, 700, 12):
			var c := img.get_pixel(x, y)
			sum += maxf(c.r, maxf(c.g, c.b))
			n += 1
		print("  y %3d  %.3f" % [y, sum / n])
	print("")
	get_tree().quit()
