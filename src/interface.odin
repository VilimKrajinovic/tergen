package tergen

StartOptions :: struct {
	width, height: int,
	title:         string,
	frame_proc:    #type proc(),
}

start :: proc(options: StartOptions) {
	platform_start(options)
}

float :: f32
float2 :: [2]f32
float3 :: [3]f32
float4 :: [4]f32

draw_rect :: proc(placement: float4, color: float4) {
	platform_draw_rect(placement, color)
}
