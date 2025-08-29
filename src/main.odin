package tergen

main :: proc() {
	start({width = 800, height = 600, title = "Tergen app", frame_proc = frame_proc})
}

frame_proc :: proc() {
	draw_rect({50, 50, 200, 80}, {0.2, 0.2, 0.8, 1})
	draw_rect({50, 40, 200, 80}, {0.2, 0.8, 0.2, 1})
}
