#+vet explicit-allocators
#+vet !unused-procedures // the harness picks; the game binary does not
package renderer

import "core:fmt"
import "core:log"
import "core:mem"

import vk "vendor:vulkan"

Pick_Push :: struct {
	x: u32,
	y: u32,
}

#assert(size_of(Pick_Push) == 8)

// The one-pixel compute shader's result buffer. Every member is a vec4, so the
// std430 layout is one 16-byte row and the Odin mirror needs no padding rules.
Pick_Raw :: struct {
	hit_info:       [4]f32, // hit, instance, face, probe inside
	sample_info:    [4]f32, // distance, probe invalid, reserved, reserved
	position:       [4]f32,
	normal:         [4]f32,
	lightmap_rect:  [4]f32,
	lightmap_texel: [4]i32,
	probe_base:     [4]i32,
	direct:         [4]f32,
	shadow:         [4]f32,
	lightmap:       [4]f32,
	probe:          [4]f32,
	emissive:       [4]f32,
}

#assert(size_of(Pick_Raw) == 192)

// A command error names bad input; a frame error means the renderer failed.
Pick_Failure :: enum {
	None,
	Command,
	Frame,
}

// The hit in renderer terms. Identity stays in the harness: the renderer only
// knows the instance custom index, which is the box order.
Pick_Hit :: struct {
	hit:            bool,
	instance:       u32,
	distance:       f32,
	position:       [3]f32,
	normal:         [3]f32,
	face:           i32,
	lightmap_rect:  [4]f32,
	lightmap_texel: [2]i32,
	probe_base:     [3]i32,
	probe_invalid:  u32,
	probe_inside:   bool,
	direct:         [3]f32,
	shadow:         [3]f32,
	lightmap:       [3]f32,
	probe:          [3]f32,
	emissive:       [3]f32,
}

// One frame with no capture, then the one-pixel dispatch against the TLAS that
// frame built. The frame advances TAA and uses the unjittered camera; it does
// not replace the render digest a capture reports.
pick :: proc(
	r: ^Renderer,
	input: Render_Input,
) -> (
	hit: Pick_Hit,
	failure: Pick_Failure,
	error: string,
) {
	at, has_at := input.pick_at.?
	if !has_at {
		return {}, .Command, fmt.aprintf("%s", "pick has no pixel", allocator = context.allocator)
	}
	if at.x < 0 || at.y < 0 ||
	   at.x >= i32(r.target.config.width) || at.y >= i32(r.target.config.height) {
		return {}, .Command, fmt.aprintf(
			"pick at (%d, %d) is outside the %dx%d capture extent",
			at.x,
			at.y,
			r.target.config.width,
			r.target.config.height,
			allocator = context.allocator,
		)
	}

	picked_index := 0
	recorded := false
	for _ in 0 ..< 2 {
		frame, begin_status := begin_frame(r, input, {})
		if begin_status == .Skipped {
			continue
		}
		if begin_status != .Ok {
			return {}, .Frame, fmt.aprintf("%s", "pick frame failed", allocator = context.allocator)
		}
		picked_index = r.frame_index
		end_status := end_frame(r, frame)
		if end_status == .Skipped {
			continue
		}
		if end_status != .Ok {
			return {}, .Frame, fmt.aprintf("%s", "pick frame failed", allocator = context.allocator)
		}
		recorded = true
		break
	}
	if !recorded {
		return {}, .Frame, fmt.aprintf("%s", "pick frame skipped", allocator = context.allocator)
	}

	mapped := r.scene.pick_mapped[picked_index]
	if mapped == nil {
		return {}, .Frame, fmt.aprintf("%s", "pick result buffer is not mapped", allocator = context.allocator)
	}
	raw := cast(^Pick_Raw)mapped
	hit.hit = raw.hit_info[0] != 0
	if !hit.hit {
		return hit, .None, ""
	}
	hit.instance = u32(raw.hit_info[1])
	hit.face = i32(raw.hit_info[2])
	hit.probe_inside = raw.hit_info[3] != 0
	hit.distance = raw.sample_info[0]
	hit.probe_invalid = u32(raw.sample_info[1])
	hit.position = {raw.position[0], raw.position[1], raw.position[2]}
	hit.normal = {raw.normal[0], raw.normal[1], raw.normal[2]}
	hit.lightmap_rect = raw.lightmap_rect
	hit.lightmap_texel = {raw.lightmap_texel[0], raw.lightmap_texel[1]}
	hit.probe_base = {raw.probe_base[0], raw.probe_base[1], raw.probe_base[2]}
	hit.direct = {raw.direct[0], raw.direct[1], raw.direct[2]}
	hit.shadow = {raw.shadow[0], raw.shadow[1], raw.shadow[2]}
	hit.lightmap = {raw.lightmap[0], raw.lightmap[1], raw.lightmap[2]}
	hit.probe = {raw.probe[0], raw.probe[1], raw.probe[2]}
	hit.emissive = {raw.emissive[0], raw.emissive[1], raw.emissive[2]}
	return hit, .None, ""
}

// The dispatch runs at the end of the frame's command buffer, after the TLAS
// build the frame forced. The host writes the cleared result before submit; the
// fence wait in end_frame makes the shader write visible.
record_pick :: proc(
	r: ^Renderer,
	command_buffer: vk.CommandBuffer,
	at: [2]i32,
) -> bool {
	if r.scene.pick_pipeline == 0 || r.scene.pick_layout == 0 {
		log.error("renderer: the pick pipeline is not created")
		return false
	}
	mapped := r.scene.pick_mapped[r.frame_index]
	if mapped == nil {
		log.error("renderer: pick result buffer is not mapped")
		return false
	}
	mem.set(mapped, 0, size_of(Pick_Raw))
	vk.CmdBindPipeline(command_buffer, .COMPUTE, r.scene.pick_pipeline)
	descriptor_set := r.scene.descriptor_sets[r.frame_index]
	vk.CmdBindDescriptorSets(
		command_buffer,
		.COMPUTE,
		r.scene.pick_layout,
		0,
		1,
		&descriptor_set,
		0,
		nil,
	)
	push := Pick_Push{x = u32(at.x), y = u32(at.y)}
	vk.CmdPushConstants(
		command_buffer,
		r.scene.pick_layout,
		{.COMPUTE},
		0,
		u32(size_of(Pick_Push)),
		&push,
	)
	vk.CmdDispatch(command_buffer, 1, 1, 1)

	barrier := vk.MemoryBarrier {
		sType = .MEMORY_BARRIER,
		srcAccessMask = {.SHADER_WRITE},
		dstAccessMask = {.HOST_READ},
	}
	vk.CmdPipelineBarrier(
		command_buffer,
		{.COMPUTE_SHADER},
		{.HOST},
		{},
		1,
		&barrier,
		0,
		nil,
		0,
		nil,
	)
	return true
}
