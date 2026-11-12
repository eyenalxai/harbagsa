#+vet explicit-allocators
package renderer

import "core:mem"

import "src:geometry"
import vk "vendor:vulkan"

MAX_DEBUG_VERTICES :: 32768

Debug_Vertex :: struct {
	position: [3]f32,
	color:    [4]f32,
}

#assert(size_of(Debug_Vertex) == 28)

Overlay :: struct {
	pipeline_format: vk.Format,
	debug_layout:    vk.PipelineLayout,
	debug_pipeline:  vk.Pipeline,

	debug_vertices:      []Debug_Vertex,
	debug_count:         int,
	debug_kind_vertices: [geometry.LINE_KIND_COUNT]int,
	debug_buffers:       [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	debug_memory:   [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	debug_mapped:   [MAX_FRAMES_IN_FLIGHT]rawptr,
}

init_overlay :: proc(r: ^Renderer) -> Error {
	o := &r.overlay
	o.debug_vertices = make([]Debug_Vertex, MAX_DEBUG_VERTICES, r.allocator)

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if !create_mapped_buffer(
			r,
			vk.DeviceSize(MAX_DEBUG_VERTICES * size_of(Debug_Vertex)),
			{.VERTEX_BUFFER},
			&o.debug_buffers[i],
			&o.debug_memory[i],
			&o.debug_mapped[i],
		) {
			return .Create_Overlay
		}
	}

	if !create_overlay_pipelines(r) {
		return .Create_Overlay
	}
	return .None
}

destroy_overlay :: proc(r: ^Renderer) {
	destroy_overlay_pipelines(r)

	if r.device != nil {
		for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
			if r.overlay.debug_mapped[i] != nil {
				vk.UnmapMemory(r.device, r.overlay.debug_memory[i])
				r.overlay.debug_mapped[i] = nil
			}
			destroy_buffer(r, &r.overlay.debug_buffers[i], &r.overlay.debug_memory[i])
		}
	}

	if r.overlay.debug_vertices != nil {
		delete(r.overlay.debug_vertices, r.allocator)
		r.overlay.debug_vertices = nil
	}
}

prepare_overlay :: proc(r: ^Renderer, debug_lines: []geometry.Line) -> bool {
	o := &r.overlay
	o.debug_count = 0
	o.debug_kind_vertices = {}

	for line in debug_lines {
		before := o.debug_count
		append_debug_vertex(o, line.from, line.color)
		append_debug_vertex(o, line.to, line.color)
		if int(line.kind) < len(o.debug_kind_vertices) {
			o.debug_kind_vertices[int(line.kind)] += o.debug_count - before
		}
	}

	frame := r.frame_index
	if o.debug_count > 0 {
		if o.debug_mapped[frame] == nil {
			return false
		}
		mem.copy(
			o.debug_mapped[frame],
			raw_data(o.debug_vertices),
			o.debug_count * size_of(Debug_Vertex),
		)
	}
	return true
}

record_overlay :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer) {
	o := &r.overlay
	frame := r.frame_index

	if o.debug_count > 0 {
		vk.CmdBindPipeline(command_buffer, .GRAPHICS, o.debug_pipeline)
		descriptor_set := r.scene.descriptor_sets[frame]
		vk.CmdBindDescriptorSets(
			command_buffer,
			.GRAPHICS,
			o.debug_layout,
			0,
			1,
			&descriptor_set,
			0,
			nil,
		)
		vertex_buffer: vk.Buffer = o.debug_buffers[frame]
		vertex_offset: vk.DeviceSize = 0
		vk.CmdBindVertexBuffers(command_buffer, 0, 1, &vertex_buffer, &vertex_offset)
		vk.CmdDraw(command_buffer, u32(o.debug_count), 1, 0, 0)
	}
}

append_debug_vertex :: proc(o: ^Overlay, position: [3]f32, color: [4]f32) {
	if o.debug_count >= len(o.debug_vertices) {
		return
	}
	o.debug_vertices[o.debug_count] = {position = position, color = color}
	o.debug_count += 1
}
