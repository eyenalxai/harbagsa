#+vet explicit-allocators
package renderer

import "core:fmt"
import "core:mem"

import "src:geometry"
import stb_easy_font "vendor:stb/easy_font"
import vk "vendor:vulkan"

// The overlay owns the two screen-facing draw paths: the world-space debug
// line list and the screen-space HUD quads. Both use host-visible vertex
// buffers that are refilled once per frame, and neither reads the scene mesh.
MAX_DEBUG_VERTICES :: 32768
MAX_HUD_VERTICES :: 24576
MAX_HUD_QUADS :: 8192

// HUD_State is the small, state-driven part of the HUD. The main loop fills it
// from the render snapshot and the cursor capture flag.
HUD_State :: struct {
	speed:    f32,
	grounded: bool,
	position: [3]f32,
	captured: bool,
}

Debug_Vertex :: struct {
	position: [3]f32,
	color:    [4]f32,
}

HUD_Vertex :: struct {
	position: [2]f32,
	color:    [4]f32,
}

#assert(size_of(Debug_Vertex) == 28)
#assert(size_of(HUD_Vertex) == 24)

DEBUG_VERTEX_SPIRV :: #load("../../build/shaders/debug.vert.spv")
DEBUG_FRAGMENT_SPIRV :: #load("../../build/shaders/debug.frag.spv")
HUD_VERTEX_SPIRV :: #load("../../build/shaders/hud.vert.spv")
HUD_FRAGMENT_SPIRV :: #load("../../build/shaders/hud.frag.spv")

HUD_TEXT_COLOR :: [4]f32{1.0, 1.0, 1.0, 1.0}
HUD_CROSSHAIR_COLOR :: [4]f32{1.0, 1.0, 1.0, 0.9}
HUD_PANEL_COLOR :: [4]f32{0.01, 0.015, 0.02, 0.65}
HUD_LINE_HEIGHT :: 12.0

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

	quads: []stb_easy_font.Quad,
}

init_overlay :: proc(r: ^Renderer) -> Error {
	o := &r.overlay
	o.debug_vertices = make([]Debug_Vertex, MAX_DEBUG_VERTICES, r.allocator)
	o.hud_vertices = make([]HUD_Vertex, MAX_HUD_VERTICES, r.allocator)
	o.quads = make([]stb_easy_font.Quad, MAX_HUD_QUADS, r.allocator)

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if !create_mapped_buffer(
			r,
			vk.DeviceSize(MAX_DEBUG_VERTICES * size_of(Debug_Vertex)),
			&o.debug_buffers[i],
			&o.debug_memory[i],
			&o.debug_mapped[i],
		) {
			return .Create_Overlay
		}
		if !create_mapped_buffer(
			r,
			vk.DeviceSize(MAX_HUD_VERTICES * size_of(HUD_Vertex)),
			&o.hud_buffers[i],
			&o.hud_memory[i],
			&o.hud_mapped[i],
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
	if r.overlay.quads != nil {
		delete(r.overlay.quads, r.allocator)
		r.overlay.quads = nil
	}
}

destroy_overlay_pipelines :: proc(r: ^Renderer) {
	if r.device == nil {
		return
	}
	if r.overlay.debug_pipeline != 0 {
		vk.DestroyPipeline(r.device, r.overlay.debug_pipeline, nil)
		r.overlay.debug_pipeline = 0
	}
	if r.overlay.debug_layout != 0 {
		vk.DestroyPipelineLayout(r.device, r.overlay.debug_layout, nil)
		r.overlay.debug_layout = 0
	}
	if r.overlay.hud_pipeline != 0 {
		vk.DestroyPipeline(r.device, r.overlay.hud_pipeline, nil)
		r.overlay.hud_pipeline = 0
	}
	if r.overlay.hud_layout != 0 {
		vk.DestroyPipelineLayout(r.device, r.overlay.hud_layout, nil)
		r.overlay.hud_layout = 0
	}
}

create_overlay_pipelines :: proc(r: ^Renderer) -> bool {
	debug_layout_info := vk.PipelineLayoutCreateInfo {
		sType          = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = 1,
		pSetLayouts    = &r.scene.descriptor_set_layout,
	}
	if !check(
		vk.CreatePipelineLayout(r.device, &debug_layout_info, nil, &r.overlay.debug_layout),
		"vkCreatePipelineLayout",
	) {
		return false
	}

	hud_push_range := vk.PushConstantRange {
		stageFlags = {.VERTEX, .FRAGMENT},
		offset     = 0,
		size       = u32(size_of([4]f32)),
	}
	hud_layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &hud_push_range,
	}
	if !check(
		vk.CreatePipelineLayout(r.device, &hud_layout_info, nil, &r.overlay.hud_layout),
		"vkCreatePipelineLayout",
	) {
		return false
	}

	debug_binding := vk.VertexInputBindingDescription {
		binding   = 0,
		stride    = u32(size_of(Debug_Vertex)),
		inputRate = .VERTEX,
	}
	debug_attributes := [2]vk.VertexInputAttributeDescription {
		{location = 0, binding = 0, format = .R32G32B32_SFLOAT, offset = 0},
		{
			location = 1,
			binding = 0,
			format = .R32G32B32A32_SFLOAT,
			offset = u32(offset_of(Debug_Vertex, color)),
		},
	}
	debug_attributes_slice := debug_attributes[:]
	if !create_overlay_pipeline(
		r,
		{
			vertex_spirv = DEBUG_VERTEX_SPIRV,
			fragment_spirv = DEBUG_FRAGMENT_SPIRV,
			name = "debug",
			binding = debug_binding,
			attributes = debug_attributes_slice,
			topology = .LINE_LIST,
			layout = r.overlay.debug_layout,
		},
		&r.overlay.debug_pipeline,
	) {
		return false
	}

	hud_binding := vk.VertexInputBindingDescription {
		binding   = 0,
		stride    = u32(size_of(HUD_Vertex)),
		inputRate = .VERTEX,
	}
	hud_attributes := [2]vk.VertexInputAttributeDescription {
		{location = 0, binding = 0, format = .R32G32_SFLOAT, offset = 0},
		{
			location = 1,
			binding = 0,
			format = .R32G32B32A32_SFLOAT,
			offset = u32(offset_of(HUD_Vertex, color)),
		},
	}
	hud_attributes_slice := hud_attributes[:]
	if !create_overlay_pipeline(
		r,
		{
			vertex_spirv = HUD_VERTEX_SPIRV,
			fragment_spirv = HUD_FRAGMENT_SPIRV,
			name = "hud",
			binding = hud_binding,
			attributes = hud_attributes_slice,
			topology = .TRIANGLE_LIST,
			layout = r.overlay.hud_layout,
		},
		&r.overlay.hud_pipeline,
	) {
		return false
	}

	r.overlay.pipeline_format = r.swapchain_format
	return true
}

Overlay_Pipeline_Desc :: struct {
	vertex_spirv:   []byte,
	fragment_spirv: []byte,
	name:           string,
	binding:        vk.VertexInputBindingDescription,
	attributes:     []vk.VertexInputAttributeDescription,
	topology:       vk.PrimitiveTopology,
	layout:         vk.PipelineLayout,
}

// create_overlay_pipeline builds the shared shape of both overlay pipelines:
// dynamic viewport and scissor, depth off, and straight alpha blending.
create_overlay_pipeline :: proc(r: ^Renderer, desc: Overlay_Pipeline_Desc, pipeline: ^vk.Pipeline) -> bool {
	binding := desc.binding
	vertex_module, vertex_ok := create_shader_module(r, desc.vertex_spirv, desc.name)
	if !vertex_ok {
		return false
	}
	fragment_module, fragment_ok := create_shader_module(r, desc.fragment_spirv, desc.name)
	if !fragment_ok {
		vk.DestroyShaderModule(r.device, vertex_module, nil)
		return false
	}
	defer {
		vk.DestroyShaderModule(r.device, vertex_module, nil)
		vk.DestroyShaderModule(r.device, fragment_module, nil)
	}

	stages := [2]vk.PipelineShaderStageCreateInfo {
		{
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.VERTEX},
			module = vertex_module,
			pName  = "main",
		},
		{
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.FRAGMENT},
			module = fragment_module,
			pName  = "main",
		},
	}

	vertex_input := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &binding,
		vertexAttributeDescriptionCount = u32(len(desc.attributes)),
		pVertexAttributeDescriptions    = raw_data(desc.attributes),
	}
	input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = desc.topology,
	}
	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}
	rasterization := vk.PipelineRasterizationStateCreateInfo {
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		cullMode    = {},
		frontFace   = .CLOCKWISE,
		lineWidth   = 1.0,
	}
	multisample := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
	}
	depth_stencil := vk.PipelineDepthStencilStateCreateInfo {
		sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable  = false,
		depthWriteEnable = false,
		depthCompareOp   = .ALWAYS,
	}
	color_attachment := vk.PipelineColorBlendAttachmentState {
		blendEnable         = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp        = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
		alphaBlendOp        = .ADD,
		colorWriteMask      = {.R, .G, .B, .A},
	}
	color_blend := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_attachment,
	}
	dynamic_states := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = u32(len(dynamic_states)),
		pDynamicStates    = &dynamic_states[0],
	}
	rendering_info := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &r.swapchain_format,
		depthAttachmentFormat   = DEPTH_FORMAT,
		stencilAttachmentFormat = .UNDEFINED,
	}
	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &rendering_info,
		stageCount          = u32(len(stages)),
		pStages             = &stages[0],
		pVertexInputState   = &vertex_input,
		pInputAssemblyState = &input_assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &rasterization,
		pMultisampleState   = &multisample,
		pDepthStencilState  = &depth_stencil,
		pColorBlendState    = &color_blend,
		pDynamicState       = &dynamic_state,
		layout              = desc.layout,
		basePipelineIndex   = -1,
	}
	if !check(
		vk.CreateGraphicsPipelines(r.device, 0, 1, &pipeline_info, nil, pipeline),
		"vkCreateGraphicsPipelines",
	) {
		return false
	}
	return true
}

create_mapped_buffer :: proc(
	r: ^Renderer,
	size: vk.DeviceSize,
	buffer: ^vk.Buffer,
	memory: ^vk.DeviceMemory,
	mapped: ^rawptr,
) -> bool {
	if !create_buffer(r, size, {.VERTEX_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT}, buffer, memory) {
		return false
	}
	if !check(vk.MapMemory(r.device, memory^, 0, size, {}, mapped), "vkMapMemory") {
		destroy_buffer(r, buffer, memory)
		return false
	}
	return true
}

// prepare_overlay refills the CPU-side vertices and uploads them into the
// mapped buffer that belongs to the frame in flight.
prepare_overlay :: proc(r: ^Renderer, debug_lines: []geometry.Line, hud: HUD_State) -> bool {
	o := &r.overlay
	o.debug_count = 0
	o.hud_count = 0

	for line in debug_lines {
		append_debug_vertex(o, line.from, line.color)
		append_debug_vertex(o, line.to, line.color)
	}

	build_hud(o, f32(r.swapchain_extent.width), f32(r.swapchain_extent.height), hud)

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
	gamma: f32 = r.swapchain_is_srgb ? 0.0 : 1.0

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
		push := [4]f32{f32(r.swapchain_extent.width), f32(r.swapchain_extent.height), gamma, 0}
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

append_hud_vertex :: proc(o: ^Overlay, position: [2]f32, color: [4]f32) {
	if o.hud_count >= len(o.hud_vertices) {
		return
	}
	o.hud_vertices[o.hud_count] = {position = position, color = color}
	o.hud_count += 1
}

hud_emit_quad :: proc(o: ^Overlay, a, b, c, d: [2]f32, color: [4]f32) {
	append_hud_vertex(o, a, color)
	append_hud_vertex(o, b, color)
	append_hud_vertex(o, c, color)
	append_hud_vertex(o, a, color)
	append_hud_vertex(o, c, color)
	append_hud_vertex(o, d, color)
}

hud_emit_rect :: proc(o: ^Overlay, x, y, width, height: f32, color: [4]f32) {
	if width <= 0 || height <= 0 {
		return
	}
	top_left := [2]f32{x, y}
	top_right := [2]f32{x + width, y}
	bottom_right := [2]f32{x + width, y + height}
	bottom_left := [2]f32{x, y + height}
	hud_emit_quad(o, top_left, top_right, bottom_right, bottom_left, color)
}

hud_emit_text :: proc(o: ^Overlay, x, y: f32, text: string, color: [4]f32, scale: f32) {
	quad_count := stb_easy_font.print(x, y, text, {255, 255, 255, 255}, o.quads, scale)
	for i in 0 ..< quad_count {
		quad := o.quads[i]
		top_left := [2]f32{quad.tl.v.x, quad.tl.v.y}
		top_right := [2]f32{quad.tr.v.x, quad.tr.v.y}
		bottom_right := [2]f32{quad.br.v.x, quad.br.v.y}
		bottom_left := [2]f32{quad.bl.v.x, quad.bl.v.y}
		hud_emit_quad(o, top_left, top_right, bottom_right, bottom_left, color)
	}
}

// display_coordinate keeps tiny negative values from printing as "-0.0".
display_coordinate :: proc(value: f32) -> f32 {
	if value > -0.05 && value < 0.05 {
		return 0
	}
	return value
}

build_hud :: proc(o: ^Overlay, width, height: f32, hud: HUD_State) {
	scale := 2.0 * clamp(height / 720.0, 1.0, 2.0)
	margin := 8.0 * scale
	padding := 5.0 * scale

	grounded := "no"
	if hud.grounded {
		grounded = "yes"
	}

	speed_buffer: [64]u8
	speed_text := fmt.bprintf(speed_buffer[:], "Speed %.1f m/s", hud.speed)
	grounded_buffer: [32]u8
	grounded_text := fmt.bprintf(grounded_buffer[:], "Grounded %s", grounded)
	position_buffer: [96]u8
	position_text := fmt.bprintf(
		position_buffer[:],
		"Position %.1f  %.1f  %.1f",
		display_coordinate(hud.position.x),
		display_coordinate(hud.position.y),
		display_coordinate(hud.position.z),
	)

	state_width := f32(
		max(
			stb_easy_font.width(speed_text),
			max(stb_easy_font.width(grounded_text), stb_easy_font.width(position_text)),
		),
	) * scale
	state_height := 3 * HUD_LINE_HEIGHT * scale
	hud_emit_rect(
		o,
		margin,
		margin,
		state_width + padding * 2,
		state_height + padding * 2,
		HUD_PANEL_COLOR,
	)
	hud_emit_text(o, margin + padding, margin + padding, speed_text, HUD_TEXT_COLOR, scale)
	hud_emit_text(
		o,
		margin + padding,
		margin + padding + HUD_LINE_HEIGHT * scale,
		grounded_text,
		HUD_TEXT_COLOR,
		scale,
	)
	hud_emit_text(
		o,
		margin + padding,
		margin + padding + 2 * HUD_LINE_HEIGHT * scale,
		position_text,
		HUD_TEXT_COLOR,
		scale,
	)

	hint_lines := [3]string {
		"WASD move    Mouse look",
		"Space jump    R reset",
		"F1 debug view    Esc release mouse",
	}
	hint_width := 0
	for line in hint_lines {
		hint_width = max(hint_width, stb_easy_font.width(line))
	}
	hint_panel_width := f32(hint_width) * scale + padding * 2
	hint_height := 3 * HUD_LINE_HEIGHT * scale
	hint_x := margin
	hint_y := height - margin - hint_height - padding * 2
	hud_emit_rect(o, hint_x, hint_y, hint_panel_width, hint_height + padding * 2, HUD_PANEL_COLOR)
	for line, index in hint_lines {
		hud_emit_text(
			o,
			hint_x + padding,
			hint_y + padding + f32(index) * HUD_LINE_HEIGHT * scale,
			line,
			HUD_TEXT_COLOR,
			scale,
		)
	}

	center_x := width * 0.5
	center_y := height * 0.5
	if !hud.captured {
		overlay_text := "Click to capture mouse"
		overlay_scale := scale * 1.1
		text_width := f32(stb_easy_font.width(overlay_text)) * overlay_scale
		text_height := f32(stb_easy_font.height(overlay_text)) * overlay_scale
		text_x := (width - text_width) * 0.5
		text_y := center_y + margin * 3 + text_height * 0.5
		panel_padding := padding * 1.5
		hud_emit_rect(
			o,
			text_x - panel_padding,
			text_y - panel_padding,
			text_width + panel_padding * 2,
			text_height + panel_padding * 2,
			HUD_PANEL_COLOR,
		)
		hud_emit_text(o, text_x, text_y, overlay_text, HUD_TEXT_COLOR, overlay_scale)
	}

	// The crosshair is emitted last so it stays on top of the panels.
	arm := 10.0 * (scale * 0.5)
	gap := 4.0 * (scale * 0.5)
	thickness := max(1.0, scale * 0.5)
	hud_emit_rect(
		o,
		center_x - gap - arm,
		center_y - thickness * 0.5,
		arm,
		thickness,
		HUD_CROSSHAIR_COLOR,
	)
	hud_emit_rect(
		o,
		center_x + gap,
		center_y - thickness * 0.5,
		arm,
		thickness,
		HUD_CROSSHAIR_COLOR,
	)
	hud_emit_rect(
		o,
		center_x - thickness * 0.5,
		center_y - gap - arm,
		thickness,
		arm,
		HUD_CROSSHAIR_COLOR,
	)
	hud_emit_rect(
		o,
		center_x - thickness * 0.5,
		center_y + gap,
		thickness,
		arm,
		HUD_CROSSHAIR_COLOR,
	)
}
