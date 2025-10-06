package tergen

import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:mem"
import "core:strings"
import sdl "vendor:sdl3"
import stbi "vendor:stb/image"

when USE_METAL {
	shader_source: []u8 = #load("./shaders/shaders.metal")
	Vec2 :: [2]f32
	Vec3 :: [3]f32
	Vec4 :: [4]f32

	Uniforms :: struct {
		mvp:  matrix[4, 4]f32,
		time: f32,
	}

	Vertex_Data :: struct {
		pos:    Vec3,
		color:  sdl.FColor,
		uv:     [2]f32,
		normal: Vec3,
	}

	WHITE :: sdl.FColor{1, 1, 1, 1}

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

		vertex_shader := load_shader(gpu, shader_source, .VERTEX, "basic_vertex", 1, 0)
		fragment_shader := load_shader(gpu, shader_source, .FRAGMENT, "basic_fragment", 1, 1)
		assert(vertex_shader != nil)
		assert(fragment_shader != nil)

		//load pixels

		img_size: [2]i32
		texture_channels: i32

		pixels := stbi.load(
			"./assets/ritica.png",
			&img_size.x,
			&img_size.y,
			nil,
			4,
		);assert(pixels != nil)
		pixels_byte_size := img_size.x * img_size.y * 4

		texture := sdl.CreateGPUTexture(
			gpu,
			sdl.GPUTextureCreateInfo {
				type = .D2,
				format = .R8G8B8A8_UNORM,
				usage = {.SAMPLER},
				width = u32(img_size.x),
				height = u32(img_size.y),
				layer_count_or_depth = 1,
				num_levels = 1,
			},
		)

		vertices := []Vertex_Data {
			{pos = {-0.5, 0.5, 0.0}, color = WHITE, uv = {0, 0}}, // tl
			{pos = {0.5, 0.5, 0.0}, color = WHITE, uv = {1, 0}}, // tr
			{pos = {-0.5, -0.5, 0.0}, color = WHITE, uv = {0, 1}}, //bl
			{pos = {0.5, -0.5, 0.0}, color = WHITE, uv = {1, 1}}, //br
		}

		indices := []u32{0, 1, 2, 2, 1, 3}

		model_data, success := load_obj("./assets/dragon.obj")
		if success {
			vertices = model_data.vertices
			indices = model_data.indices
			free_obj_data(&model_data)
		}

		num_vertices := u32(len(vertices))
		num_indices := u32(len(indices))
		vertices_byte_size := len(vertices) * size_of(vertices[0])
		indices_byte_size := len(indices) * size_of(indices[0])

		vertex_buf := sdl.CreateGPUBuffer(
			gpu,
			sdl.GPUBufferCreateInfo{usage = {.VERTEX}, size = u32(vertices_byte_size)},
		)

		index_buf := sdl.CreateGPUBuffer(
			gpu,
			sdl.GPUBufferCreateInfo{usage = {.INDEX}, size = u32(indices_byte_size)},
		)


		//Transfer memory to GPU
		transfer_buf := sdl.CreateGPUTransferBuffer(
			gpu,
			sdl.GPUTransferBufferCreateInfo {
				usage = .UPLOAD,
				size = u32(vertices_byte_size + indices_byte_size),
			},
		)

		transfer_mem := transmute([^]byte)sdl.MapGPUTransferBuffer(gpu, transfer_buf, false)
		mem.copy(transfer_mem, raw_data(vertices), vertices_byte_size)
		mem.copy(transfer_mem[vertices_byte_size:], raw_data(indices), indices_byte_size)
		sdl.UnmapGPUTransferBuffer(gpu, transfer_buf)

		//Texture transfer buf
		tex_transfer_buf := sdl.CreateGPUTransferBuffer(
			gpu,
			sdl.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = u32(pixels_byte_size)},
		)

		tex_transfer_mem := sdl.MapGPUTransferBuffer(gpu, tex_transfer_buf, false)
		mem.copy(tex_transfer_mem, pixels, int(pixels_byte_size))
		sdl.UnmapGPUTransferBuffer(gpu, tex_transfer_buf)

		copy_command_buffer := sdl.AcquireGPUCommandBuffer(gpu)
		copy_pass := sdl.BeginGPUCopyPass(copy_command_buffer)

		sdl.UploadToGPUBuffer(
			copy_pass,
			{transfer_buffer = transfer_buf},
			{buffer = vertex_buf, size = u32(vertices_byte_size)},
			false,
		)

		sdl.UploadToGPUBuffer(
			copy_pass,
			{transfer_buffer = transfer_buf, offset = u32(vertices_byte_size)},
			{buffer = index_buf, size = u32(indices_byte_size)},
			false,
		)

		sdl.UploadToGPUTexture(
			copy_pass,
			{transfer_buffer = tex_transfer_buf},
			{texture = texture, w = u32(img_size.x), h = u32(img_size.y), d = 1},
			false,
		)

		sdl.EndGPUCopyPass(copy_pass)
		ok = sdl.SubmitGPUCommandBuffer(copy_command_buffer);assert(ok)

		sdl.ReleaseGPUTransferBuffer(gpu, transfer_buf)
		sdl.ReleaseGPUTransferBuffer(gpu, tex_transfer_buf)

		sampler := sdl.CreateGPUSampler(gpu, {})

		window_size: [2]i32
		ok = sdl.GetWindowSize(window, &window_size.x, &window_size.y);assert(ok)

	// Create depth texture
	depth_texture := sdl.CreateGPUTexture(
		gpu,
		sdl.GPUTextureCreateInfo {
			type = .D2,
			format = .D32_FLOAT,
			usage = {.DEPTH_STENCIL_TARGET},
			width = u32(window_size.x),
			height = u32(window_size.y),
			layer_count_or_depth = 1,
			num_levels = 1,
		},
	)

		vertex_attribtues := []sdl.GPUVertexAttribute {
			{location = 0, format = .FLOAT3, offset = u32(offset_of(Vertex_Data, pos))},
			{location = 1, format = .FLOAT4, offset = u32(offset_of(Vertex_Data, color))},
			{location = 2, format = .FLOAT2, offset = u32(offset_of(Vertex_Data, uv))},
			{location = 3, format = .FLOAT3, offset = u32(offset_of(Vertex_Data, normal))},
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
					has_depth_stencil_target = true,
					depth_stencil_format = .D32_FLOAT,
				},
				primitive_type = .TRIANGLELIST,
				rasterizer_state = {cull_mode = .NONE},
				depth_stencil_state = {
					enable_depth_test = true,
					enable_depth_write = true,
					compare_op = .LESS,
				},
			},
		);assert(graphics_pipeline != nil)


		sdl.ReleaseGPUShader(gpu, vertex_shader)
		sdl.ReleaseGPUShader(gpu, fragment_shader)


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
				linalg.matrix4_translate_f32({0, -4, -14}) *
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

			depth_stencil_target_info := sdl.GPUDepthStencilTargetInfo {
				texture         = depth_texture,
				clear_depth     = 1.0,
				load_op         = .CLEAR,
				store_op        = .DONT_CARE,
				stencil_load_op = .DONT_CARE,
				stencil_store_op = .DONT_CARE,
			}

			render_pass := sdl.BeginGPURenderPass(command_buffer, &color_target_info, 1, &depth_stencil_target_info)
			sdl.BindGPUGraphicsPipeline(render_pass, graphics_pipeline)
			sdl.BindGPUVertexBuffers(
				render_pass,
				0,
				&(sdl.GPUBufferBinding{buffer = vertex_buf, offset = 0}),
				1,
			)
			sdl.BindGPUIndexBuffer(render_pass, {buffer = index_buf}, ._32BIT)
			sdl.PushGPUVertexUniformData(command_buffer, 0, &uniforms, size_of(uniforms))
			sdl.BindGPUFragmentSamplers(
				render_pass,
				0,
				&(sdl.GPUTextureSamplerBinding{texture = texture, sampler = sampler}),
				1,
			)
			sdl.DrawGPUIndexedPrimitives(render_pass, num_indices, 1, 0, 0, 0)
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
		num_samplers: u32,
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
				num_samplers = num_samplers,
			},
		)
	}
}
