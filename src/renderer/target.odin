#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

Target_Kind :: enum {
	Swapchain,
	Offscreen,
}

Target_Config :: struct {
	width:   u32,
	height:  u32,
	format:  vk.Format,
	is_srgb: bool,
}

Readback :: struct {
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
	mapped: rawptr,
	pixels: []u8,
	size:   vk.DeviceSize,
	slots:  u32,
}

// The offscreen target owns one color image, so a second submission would
// write it while the first is still reading it. The swapchain rotates images and
// keeps both slots busy.
frames_in_flight :: proc(kind: Target_Kind) -> int {
	switch kind {
	case .Offscreen:
		return 1
	case .Swapchain:
		return MAX_FRAMES_IN_FLIGHT
	}
	return 1
}

Target :: struct {
	kind:      Target_Kind,
	config:    Target_Config,
	surface:   vk.SurfaceKHR,
	swapchain: vk.SwapchainKHR,
	dirty:     bool,
	images:    []vk.Image,
	views:     []vk.ImageView,
	// The present wait may still be pending when a frame slot submits again, so
	// each swapchain image owns its signal semaphore.
	render_finished: []vk.Semaphore,
	color:           Image,
	readback:        Readback,
}

create_target :: proc(r: ^Renderer, width, height: u32) -> Error {
	switch r.target.kind {
	case .Swapchain:
		return init_swapchain_target(r)
	case .Offscreen:
		return init_offscreen_target(r, width, height)
	}
	return .Create_Target
}

destroy_target :: proc(r: ^Renderer) {
	switch r.target.kind {
	case .Swapchain:
		destroy_swapchain(r)
		if r.instance != nil && r.target.surface != 0 {
			r.platform.destroy_surface(r.platform.user, r.instance, r.target.surface)
			r.target.surface = 0
		}
	case .Offscreen:
		destroy_image(r, &r.target.color)
		delete_target_slices(r)
	}
	destroy_readback(r)
	r.target.config = {}
}

@(private)
create_readback :: proc(r: ^Renderer, width, height: u32, slots: u32 = 1) -> bool {
	count := max(slots, 1)
	size := vk.DeviceSize(width) * vk.DeviceSize(height) * MAX_CAPTURE_TEXEL_BYTES * vk.DeviceSize(count)
	if size == 0 {
		return false
	}
	if !create_mapped_buffer(
		r,
		size,
		{.TRANSFER_DST},
		&r.target.readback.buffer,
		&r.target.readback.memory,
		&r.target.readback.mapped,
	) {
		return false
	}
	r.target.readback.size = size
	r.target.readback.slots = count
	r.target.readback.pixels = make([]u8, int(size), r.allocator)
	return true
}

// A multi-target capture needs one slot per target. Growing the buffer is rare,
// so wait for the device before replacing a buffer an earlier frame may read.
ensure_readback_slots :: proc(r: ^Renderer, slots: u32) -> bool {
	if r.target.readback.slots >= slots {
		return true
	}
	if !check(vk.DeviceWaitIdle(r.device), "vkDeviceWaitIdle") {
		return false
	}
	width := r.target.config.width
	height := r.target.config.height
	destroy_readback(r)
	return create_readback(r, width, height, slots)
}

destroy_readback :: proc(r: ^Renderer) {
	if r.device != nil && r.target.readback.mapped != nil {
		vk.UnmapMemory(r.device, r.target.readback.memory)
		r.target.readback.mapped = nil
	}
	destroy_buffer(r, &r.target.readback.buffer, &r.target.readback.memory)
	if r.target.readback.pixels != nil {
		delete(r.target.readback.pixels, r.allocator)
		r.target.readback.pixels = nil
	}
	r.target.readback.size = 0
	r.target.readback.slots = 0
}

@(private)
delete_target_slices :: proc(r: ^Renderer) {
	if r.target.views != nil {
		delete(r.target.views, r.allocator)
		r.target.views = nil
	}
	if r.target.images != nil {
		delete(r.target.images, r.allocator)
		r.target.images = nil
	}
	if r.target.render_finished != nil {
		delete(r.target.render_finished, r.allocator)
		r.target.render_finished = nil
	}
}


target_extent :: proc(r: ^Renderer) -> (width, height: u32) {
	return r.target.config.width, r.target.config.height
}
