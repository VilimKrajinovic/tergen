package tergen

StartOptions :: struct {
	width, height: int,
	title:         string,
}

start :: proc(options: StartOptions) {
	platform_start(options)
}

