package tergen

import "core:fmt"
import "core:log"
import "core:strings"
import sdl "vendor:sdl3"

when USE_METAL {
	shader_source: string = #load("shaders.metal")

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

		vertex_shader_info := sdl.GPUShaderCreateInfo {
			code       = raw_data(shader_source),
			code_size  = len(shader_source),
			entrypoint = "basic_vertex",
			format     = {.MSL},
			stage      = .VERTEX,
		}
		vertex_shader := sdl.CreateGPUShader(gpu, vertex_shader_info)
		assert(vertex_shader != nil)

		fragment_shader_info := sdl.GPUShaderCreateInfo {
			code       = raw_data(shader_source),
			code_size  = len(shader_source),
			entrypoint = "basic_fragment",
			format     = {.MSL},
			stage      = .FRAGMENT,
		}

		fragment_shader := sdl.CreateGPUShader(gpu, fragment_shader_info)
		assert(fragment_shader != nil)
		color_targets := []sdl.GPUColorTargetDescription{{format = .B8G8R8A8_UNORM}}
		graphics_pipeline_info := sdl.GPUGraphicsPipelineCreateInfo {
			vertex_shader = vertex_shader,
			fragment_shader = fragment_shader,
			target_info = {
				num_color_targets = 1,
				color_target_descriptions = raw_data(color_targets),
			},
			primitive_type = .TRIANGLESTRIP,
		}
		graphics_pipeline := sdl.CreateGPUGraphicsPipeline(gpu, graphics_pipeline_info)
		assert(graphics_pipeline != nil)


		for {
			// handle events
			event: sdl.Event
			for sdl.PollEvent(&event) {
				#partial switch event.type {
				case .QUIT:
					user_quit = true
				}
			}

			// update game state


			//render
			command_buffer := sdl.AcquireGPUCommandBuffer(gpu)
			swapchain_texture: ^sdl.GPUTexture
			ok = sdl.WaitAndAcquireGPUSwapchainTexture(
				command_buffer,
				window,
				&swapchain_texture,
				nil,
				nil,
			);assert(ok)

			color_target_info := sdl.GPUColorTargetInfo {
				texture     = swapchain_texture,
				clear_color = {0, 1.0, 1.0, 1.0},
				load_op     = .CLEAR,
				store_op    = .STORE,
			}
			render_pass := sdl.BeginGPURenderPass(command_buffer, &color_target_info, 1, nil)
			sdl.BindGPUGraphicsPipeline(render_pass, graphics_pipeline)
			sdl.DrawGPUPrimitives(render_pass, 4, 1, 0, 0)
			sdl.EndGPURenderPass(render_pass)
			ok = sdl.SubmitGPUCommandBuffer(command_buffer);assert(ok)

			if user_quit do break
		}
	}

	platform_draw_rect :: proc(placement: float4, color: float4) {

	}
}
