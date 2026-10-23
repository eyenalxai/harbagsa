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
}

Target :: struct {
	kind:      Target_Kind,
	config:    Target_Config,
	surface:   vk.SurfaceKHR,
	swapchain: vk.SwapchainKHR,
	dirty:     bool,
	images:    []vk.Image,
	views:     []vk.ImageView,
	depth:     []Image,
	color:     Image,
	readback:  Readback,
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
		destroy_swapchain_images(r)
		if r.device != nil && r.target.swapchain != 0 {
			vk.DestroySwapchainKHR(r.device, r.target.swapchain, nil)
			r.target.swapchain = 0
		}
		if r.instance != nil && r.target.surface != 0 {
			r.platform.destroy_surface(r.platform.user, r.instance, r.target.surface)
			r.target.surface = 0
		}
	case .Offscreen:
		destroy_image(r, &r.target.color)
		for &image in r.target.depth {
			destroy_image(r, &image)
		}
	}
	destroy_readback(r)
	delete_target_slices(r)
	r.target.config = {}
}

create_readback :: proc(r: ^Renderer, width, height: u32) -> bool {
	size := vk.DeviceSize(width) * vk.DeviceSize(height) * 4
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
	r.target.readback.pixels = make([]u8, int(size), r.allocator)
	return true
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
	if r.target.depth != nil {
		delete(r.target.depth, r.allocator)
		r.target.depth = nil
	}
}
