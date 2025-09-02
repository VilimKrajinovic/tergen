package tergen

import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:strings"
import sdl "vendor:sdl3"

when USE_METAL {
	shader_source: []u8 = #load("./shaders/shaders.metal")
	//
	platform_start :: proc(options: StartOptions) {
		sdl.SetLogPriorities(.VERBOSE)
		ok := sdl.Init({.VIDEO, .EVENTS});assert(ok)

		window := sdl.CreateWindow(
			strings.clone_to_cstring(options.title),
			auto_cast options.width,
			auto_cast options.height,
			{.METAL, .RESIZABLE},
		);assert(window != nil)

		sdl.ShowWindow(window)
		user_quit := false

		gpu := sdl.CreateGPUDevice({.METALLIB}, true, "metal");assert(gpu != nil)
		ok = sdl.ClaimWindowForGPUDevice(gpu, window);assert(ok)

		vertex_shader := load_shader(gpu, shader_source, .VERTEX, "basic_vertex", 1)
		assert(vertex_shader != nil)
		fragment_shader := load_shader(gpu, shader_source, .FRAGMENT, "basic_fragment", 0)
		assert(fragment_shader != nil)

		graphics_pipeline_info := sdl.GPUGraphicsPipelineCreateInfo {
			vertex_shader = vertex_shader,
			fragment_shader = fragment_shader,
			target_info = {
				num_color_targets = 1,
				color_target_descriptions = &(sdl.GPUColorTargetDescription {
						format = sdl.GetGPUSwapchainTextureFormat(gpu, window),
					}),
			},
			primitive_type = .TRIANGLESTRIP,
		}
		graphics_pipeline := sdl.CreateGPUGraphicsPipeline(gpu, graphics_pipeline_info)
		assert(graphics_pipeline != nil)

		sdl.ReleaseGPUShader(gpu, vertex_shader)
		sdl.ReleaseGPUShader(gpu, fragment_shader)


		window_size: [2]i32
		ok = sdl.GetWindowSize(window, &window_size.x, &window_size.y);assert(ok)
		projection_matrix := linalg.matrix4_perspective_f32(
			70,
			f32(window_size.x) / f32(window_size.y),
			0.0001,
			1000,
		)

		ROTATION_SPEED := linalg.to_radians(f32(90))
		rotation := f32(0)

		Uniforms :: struct {
			mvp: matrix[4, 4]f32,
		}

		last_ticks := sdl.GetTicks()

		for {
			//update delta time
			new_ticks := sdl.GetTicks()
			delta_time := f32(new_ticks - last_ticks) / 1000
			last_ticks = new_ticks


			// handle events
			event: sdl.Event
			for sdl.PollEvent(&event) {
				#partial switch event.type {
				case .QUIT:
					user_quit = true
				}
			}

			// update game state


			//render passes
			command_buffer := sdl.AcquireGPUCommandBuffer(gpu)
			swapchain_texture: ^sdl.GPUTexture
			ok = sdl.WaitAndAcquireGPUSwapchainTexture(
				command_buffer,
				window,
				&swapchain_texture,
				nil,
				nil,
			);assert(ok)

			rotation += ROTATION_SPEED * delta_time
			model_matrix :=
				linalg.matrix4_translate_f32({0, 0, -5}) *
				linalg.matrix4_rotate_f32(rotation, {0, 1, 0})

			uniforms: Uniforms = {
				mvp = projection_matrix * model_matrix,
			}


			color_target_info := sdl.GPUColorTargetInfo {
				texture     = swapchain_texture,
				clear_color = {0, 1.0, 1.0, 1.0},
				load_op     = .CLEAR,
				store_op    = .STORE,
			}
			render_pass := sdl.BeginGPURenderPass(command_buffer, &color_target_info, 1, nil)
			sdl.BindGPUGraphicsPipeline(render_pass, graphics_pipeline)
			sdl.PushGPUVertexUniformData(command_buffer, 0, &uniforms, size_of(uniforms))
			sdl.DrawGPUPrimitives(render_pass, 4, 1, 0, 0)
			sdl.EndGPURenderPass(render_pass)
			ok = sdl.SubmitGPUCommandBuffer(command_buffer);assert(ok)

			if user_quit do break
		}
	}

	load_shader :: proc(
		device: ^sdl.GPUDevice,
		code: []u8,
		stage: sdl.GPUShaderStage,
		entry_point: cstring,
		num_uniform_buffers: u32,
	) -> ^sdl.GPUShader {
		return sdl.CreateGPUShader(
			device,
			sdl.GPUShaderCreateInfo {
				code = raw_data(code),
				code_size = len(code),
				entrypoint = entry_point,
				format = {.MSL},
				stage = stage,
				num_uniform_buffers = num_uniform_buffers,
			},
		)
	}

	platform_draw_rect :: proc(placement: float4, color: float4) {

	}
}
