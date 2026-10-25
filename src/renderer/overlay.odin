#+vet explicit-allocators
package renderer

import "core:mem"

import "src:geometry"
import vk "vendor:vulkan"

MAX_DEBUG_VERTICES :: 32768
MAX_HUD_VERTICES :: 24576

Debug_Vertex :: struct {
	position: [3]f32,
	color:    [4]f32,
}

HUD_Vertex :: struct {
	position: [2]f32,
	color:    [4]f32,
	uv:       [2]f32,
}

#assert(size_of(Debug_Vertex) == 28)
#assert(size_of(HUD_Vertex) == 32)

Overlay :: struct {
	pipeline_format: vk.Format,
	debug_layout:    vk.PipelineLayout,
	debug_pipeline:  vk.Pipeline,
	hud_layout:      vk.PipelineLayout,
	hud_pipeline:    vk.Pipeline,

	debug_vertices: []Debug_Vertex,
	debug_count:    int,
	debug_buffers:  [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	debug_memory:   [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	debug_mapped:   [MAX_FRAMES_IN_FLIGHT]rawptr,

	hud_vertices: []HUD_Vertex,
	hud_count:    int,
	hud_buffers:  [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	hud_memory:   [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	hud_mapped:   [MAX_FRAMES_IN_FLIGHT]rawptr,

	theme: UI_Theme,

	atlas:                Text_Atlas,
	atlas_applied_weight: f32,
	atlas_worker:         Text_Atlas_Worker,
	atlas_image:   Image,
	atlas_sampler: vk.Sampler,
	atlas_layout:  vk.DescriptorSetLayout,
	atlas_pool:    vk.DescriptorPool,
	atlas_set:     vk.DescriptorSet,
}

init_overlay :: proc(r: ^Renderer) -> Error {
	o := &r.overlay
	o.theme = ui_theme_init(r.target.config.height)
	o.debug_vertices = make([]Debug_Vertex, MAX_DEBUG_VERTICES, r.allocator)
	o.hud_vertices = make([]HUD_Vertex, MAX_HUD_VERTICES, r.allocator)

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
		if !create_mapped_buffer(
			r,
			vk.DeviceSize(MAX_HUD_VERTICES * size_of(HUD_Vertex)),
			{.VERTEX_BUFFER},
			&o.hud_buffers[i],
			&o.hud_memory[i],
			&o.hud_mapped[i],
		) {
			return .Create_Overlay
		}
	}

	if !init_text_atlas_resources(r) {
		return .Create_Overlay
	}
	if !create_overlay_pipelines(r) {
		return .Create_Overlay
	}
	return .None
}

destroy_overlay :: proc(r: ^Renderer) {
	destroy_overlay_pipelines(r)
	destroy_text_atlas_resources(r)

	if r.device != nil {
		for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
			if r.overlay.debug_mapped[i] != nil {
				vk.UnmapMemory(r.device, r.overlay.debug_memory[i])
				r.overlay.debug_mapped[i] = nil
			}
			destroy_buffer(r, &r.overlay.debug_buffers[i], &r.overlay.debug_memory[i])

			if r.overlay.hud_mapped[i] != nil {
				vk.UnmapMemory(r.device, r.overlay.hud_memory[i])
				r.overlay.hud_mapped[i] = nil
			}
			destroy_buffer(r, &r.overlay.hud_buffers[i], &r.overlay.hud_memory[i])
		}
	}

	if r.overlay.debug_vertices != nil {
		delete(r.overlay.debug_vertices, r.allocator)
		r.overlay.debug_vertices = nil
	}
	if r.overlay.hud_vertices != nil {
		delete(r.overlay.hud_vertices, r.allocator)
		r.overlay.hud_vertices = nil
	}
}

prepare_overlay :: proc(r: ^Renderer, debug_lines: []geometry.Line, hud: HUD_Frame) -> bool {
	o := &r.overlay
	o.debug_count = 0
	o.hud_count = 0

	for line in debug_lines {
		append_debug_vertex(o, line.from, line.color)
		append_debug_vertex(o, line.to, line.color)
	}

	requested_weight := hud.weight
	if requested_weight == 0 {
		requested_weight = BASE_WEIGHT
	}
	if !text_atlas_sync(r, requested_weight) {
		return false
	}
	o.theme = ui_theme_init(r.target.config.height, o.atlas_applied_weight)
	build_hud(o, f32(r.target.config.width), f32(r.target.config.height), hud)

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
	if o.hud_count > 0 {
		if o.hud_mapped[frame] == nil {
			return false
		}
		mem.copy(o.hud_mapped[frame], raw_data(o.hud_vertices), o.hud_count * size_of(HUD_Vertex))
	}
	return true
}

record_overlay :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer) {
	o := &r.overlay
	frame := r.frame_index
	gamma := srgb_gamma(r)

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

	if o.hud_count > 0 {
		vk.CmdBindPipeline(command_buffer, .GRAPHICS, o.hud_pipeline)
		descriptor_set := o.atlas_set
		vk.CmdBindDescriptorSets(
			command_buffer,
			.GRAPHICS,
			o.hud_layout,
			0,
			1,
			&descriptor_set,
			0,
			nil,
		)
		push := [4]f32{f32(r.target.config.width), f32(r.target.config.height), gamma, 0}
		vk.CmdPushConstants(
			command_buffer,
			o.hud_layout,
			{.VERTEX, .FRAGMENT},
			0,
			u32(size_of(push)),
			&push,
		)
		vertex_buffer: vk.Buffer = o.hud_buffers[frame]
		vertex_offset: vk.DeviceSize = 0
		vk.CmdBindVertexBuffers(command_buffer, 0, 1, &vertex_buffer, &vertex_offset)
		vk.CmdDraw(command_buffer, u32(o.hud_count), 1, 0, 0)
	}
}

append_debug_vertex :: proc(o: ^Overlay, position: [3]f32, color: [4]f32) {
	if o.debug_count >= len(o.debug_vertices) {
		return
	}
	o.debug_vertices[o.debug_count] = {position = position, color = color}
	o.debug_count += 1
}

append_hud_vertex :: proc(o: ^Overlay, position: [2]f32, color: [4]f32, uv: [2]f32) {
	if o.hud_count >= len(o.hud_vertices) {
		return
	}
	o.hud_vertices[o.hud_count] = {position = position, color = color, uv = uv}
	o.hud_count += 1
}
