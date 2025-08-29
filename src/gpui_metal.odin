package tergen

import "core:fmt"
import "core:strings"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import sdl "vendor:sdl2"

when USE_METAL {
	shader_source: string = #load("shaders.metal")

	NS_String :: proc(s: string) -> ^NS.String {
		return NS.String.alloc()->initWithOdinString(s)
	}

	platform_start :: proc(options: StartOptions) {
		sdl.Init({.VIDEO, .EVENTS})
		window := sdl.CreateWindow(
			strings.clone_to_cstring(options.title),
			sdl.WINDOWPOS_UNDEFINED,
			sdl.WINDOWPOS_UNDEFINED,
			auto_cast options.width,
			auto_cast options.height,
			{.METAL, .ALLOW_HIGHDPI, .RESIZABLE},
		)
		sdl.ShowWindow(window)

		user_quit := false

		sdl.SetHint(sdl.HINT_RENDER_DRIVER, "metal")
		renderer := sdl.CreateRenderer(window, -1, {.PRESENTVSYNC})

		metal_layer := cast(^CA.MetalLayer)sdl.RenderGetMetalLayer(renderer)
		metal_layer->setPixelFormat(.BGRA8Unorm_sRGB)

		metal_device := metal_layer->device()
		command_queue := metal_device->newCommandQueue()

		shader_library, err := metal_device->newLibraryWithSource(NS_String(shader_source), nil)
		if err != nil {
			fmt.println(err->localizedDescription()->odinString())
			return
		}

		vertex_fn := shader_library->newFunctionWithName(NS.AT("basic_vertex"))
		fragment_fn := shader_library->newFunctionWithName(NS.AT("basic_fragment"))

		pipeline_desc := MTL.RenderPipelineDescriptor.alloc()->init()
		pipeline_desc->setVertexFunction(vertex_fn)
		pipeline_desc->setFragmentFunction(fragment_fn)

		color_attachment_desc := pipeline_desc->colorAttachments()->object(0)
		color_attachment_desc->setPixelFormat(.BGRA8Unorm_sRGB)

		pipeline, perr := metal_device->newRenderPipelineStateWithDescriptor(pipeline_desc)

		if perr != nil {
			fmt.println(perr->localizedDescription()->odinString())
			return
		}


		for {
			event: sdl.Event
			for sdl.PollEvent(&event) {
				#partial switch event.type {
				case .QUIT:
					user_quit = true
				}
			}

			NS.scoped_autoreleasepool()

			drawable := metal_layer->nextDrawable()

			pass_descriptor := MTL.RenderPassDescriptor.renderPassDescriptor()

			color_attachment := pass_descriptor->colorAttachments()->object(0)
			color_attachment->setClearColor({0.2, 0.2, 0.9, 1.0})
			color_attachment->setLoadAction(.Clear)
			color_attachment->setStoreAction(.Store)
			color_attachment->setTexture(drawable->texture())

			command_buffer := command_queue->commandBuffer()
			command_encoder := command_buffer->renderCommandEncoderWithDescriptor(pass_descriptor)

			command_encoder->setRenderPipelineState(pipeline)
			command_encoder->drawPrimitivesWithInstanceCount(.TriangleStrip, 0, 4, 1)


			command_encoder->endEncoding()
			command_buffer->presentDrawable(drawable)
			command_buffer->commit()

			if user_quit do break
		}
	}

	platform_draw_rect :: proc(placement: float4, color: float4) {

	}
}
