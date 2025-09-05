package tergen

import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:mem"
import "core:strings"
import sdl "vendor:sdl3"

when USE_METAL {
	shader_source: []u8 = #load("./shaders/shaders.metal")
	Vec3 :: [3]f32
	Vec4 :: [4]f32

	Uniforms :: struct {
		mvp:  matrix[4, 4]f32,
		time: f32,
	}

	Vertex_Data :: struct {
		pos:   Vec3,
		color: Vec4,
	}

	ROTATION_SPEED := linalg.to_radians(f32(90))

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
		fragment_shader := load_shader(gpu, shader_source, .FRAGMENT, "basic_fragment", 1)
		assert(fragment_shader != nil)


		vertices := []Vertex_Data {
			{pos = {-0.5, -0.5, 0.0}, color = {1, 0, 0, 1}},
			{pos = {0.0, 0.5, 0.0}, color = {0, 1, 0, 1}},
			{pos = {0.5, -0.5, 0.0}, color = {0, 0, 1, 1}},
		}
		vertices_byte_size := len(vertices) * size_of(vertices[0])

		vertex_buf := sdl.CreateGPUBuffer(
			gpu,
			sdl.GPUBufferCreateInfo{usage = {.VERTEX}, size = u32(vertices_byte_size)},
		)

		transfer_buf := sdl.CreateGPUTransferBuffer(
			gpu,
			sdl.GPUTransferBufferCreateInfo {
				usage = .UPLOAD,
				size = u32(vertices_byte_size),
				props = 0,
			},
		)

		//Transfer memory to GPU
		transfer_mem := sdl.MapGPUTransferBuffer(gpu, transfer_buf, false)
		mem.copy(transfer_mem, raw_data(vertices), vertices_byte_size)
		sdl.UnmapGPUTransferBuffer(gpu, transfer_buf)

		copy_command_buffer := sdl.AcquireGPUCommandBuffer(gpu)
		copy_pass := sdl.BeginGPUCopyPass(copy_command_buffer)

		sdl.UploadToGPUBuffer(
			copy_pass,
			{transfer_buffer = transfer_buf},
			{buffer = vertex_buf, size = u32(vertices_byte_size)},
			false,
		)


		sdl.EndGPUCopyPass(copy_pass)
		ok = sdl.SubmitGPUCommandBuffer(copy_command_buffer);assert(ok)

		sdl.ReleaseGPUTransferBuffer(gpu, transfer_buf)

		vertex_attribtues := []sdl.GPUVertexAttribute{
      {location = 0, format = .FLOAT3, offset = u32(offset_of(Vertex_Data, pos))},
      {location = 1, format = .FLOAT4, offset = u32(offset_of(Vertex_Data, color))},
    }

		graphics_pipeline := sdl.CreateGPUGraphicsPipeline(
			gpu,
			sdl.GPUGraphicsPipelineCreateInfo {
				vertex_shader = vertex_shader,
				fragment_shader = fragment_shader,
				vertex_input_state = sdl.GPUVertexInputState {
					num_vertex_buffers = 1,
					vertex_buffer_descriptions = &(sdl.GPUVertexBufferDescription {
							slot = 0,
							pitch = size_of(Vertex_Data),
						}),
					num_vertex_attributes = u32(len(vertex_attribtues)),
					vertex_attributes = raw_data(vertex_attribtues),
				},
				target_info = {
					num_color_targets = 1,
					color_target_descriptions = &(sdl.GPUColorTargetDescription {
							format = sdl.GetGPUSwapchainTextureFormat(gpu, window),
						}),
				},
				primitive_type = .TRIANGLESTRIP,
			},
		);assert(graphics_pipeline != nil)


		sdl.ReleaseGPUShader(gpu, vertex_shader)
		sdl.ReleaseGPUShader(gpu, fragment_shader)


		window_size: [2]i32
		ok = sdl.GetWindowSize(window, &window_size.x, &window_size.y);assert(ok)
		projection_matrix := linalg.matrix4_perspective_f32(
			linalg.to_radians(f32(70)),
			f32(window_size.x) / f32(window_size.y),
			0.0001,
			1000,
		)

		rotation := f32(0)
		elapsed_time := f32(0)
		last_ticks := sdl.GetTicks()

		for {
			//update delta time
			new_ticks := sdl.GetTicks()
			delta_time := f32(new_ticks - last_ticks) / 1000
			elapsed_time += delta_time
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
				mvp  = projection_matrix * model_matrix,
				time = elapsed_time,
			}

			color_target_info := sdl.GPUColorTargetInfo {
				texture     = swapchain_texture,
				clear_color = {0, 0.5, 0.5, 1.0},
				load_op     = .CLEAR,
				store_op    = .STORE,
			}
			render_pass := sdl.BeginGPURenderPass(command_buffer, &color_target_info, 1, nil)
			sdl.BindGPUGraphicsPipeline(render_pass, graphics_pipeline)
			sdl.BindGPUVertexBuffers(
				render_pass,
				0,
				&(sdl.GPUBufferBinding{buffer = vertex_buf, offset = 0}),
				1,
			)
			sdl.PushGPUVertexUniformData(command_buffer, 0, &uniforms, size_of(uniforms))
			sdl.DrawGPUPrimitives(render_pass, 3, 1, 0, 0)
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
