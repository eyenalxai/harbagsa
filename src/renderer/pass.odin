#+vet explicit-allocators
package renderer

import "src:geometry"
import "src:perf"
import vk "vendor:vulkan"

// One render scope. A builder fills the attachments, load and store, pipeline,
// and the barrier procs. The recorder owns begin, end, viewport, and the order
// in which the procs run.
Pass :: struct {
	name:         perf.Pass,
	barriers:     proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass),
	after:        proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass),
	rendering:    vk.RenderingInfo,
	attachments:  [3]vk.RenderingAttachmentInfo,
	depth:        vk.RenderingAttachmentInfo,
	pipeline:     vk.Pipeline,
	layout:       vk.PipelineLayout,
	stages:       vk.ShaderStageFlags,
	bind_camera:  bool,
	has_rendering: bool,
	draw:         proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass),
	image_index:  u32,
	boxes:        []geometry.Box,
}

record_pass :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	if pass.barriers != nil {
		pass.barriers(r, command_buffer, pass)
	}
	if pass.has_rendering {
		extent := pass.rendering.renderArea.extent
		vk.CmdBeginRendering(command_buffer, &pass.rendering)
		set_viewport(command_buffer, extent.width, extent.height)
		if pass.pipeline != 0 {
			vk.CmdBindPipeline(command_buffer, .GRAPHICS, pass.pipeline)
		}
		if pass.bind_camera {
			bind_camera(
				command_buffer,
				pass.layout,
				r.scene.descriptor_sets[r.frame_index],
			)
		}
		if pass.draw != nil {
			pass.draw(r, command_buffer, pass)
		}
		vk.CmdEndRendering(command_buffer)
	} else if pass.draw != nil {
		pass.draw(r, command_buffer, pass)
	}
	if pass.after != nil {
		pass.after(r, command_buffer, pass)
	}
}
