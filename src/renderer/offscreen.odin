#+vet explicit-allocators
package renderer

import "core:log"

import vk "vendor:vulkan"

OFFSCREEN_FORMATS :: []vk.Format {
	.R8G8B8A8_SRGB,
	.B8G8R8A8_SRGB,
	.R8G8B8A8_UNORM,
	.B8G8R8A8_UNORM,
}

init_offscreen_target :: proc(r: ^Renderer, width, height: u32) -> Error {
	if width == 0 || height == 0 {
		log.errorf("renderer: offscreen target needs a size, got %vx%v", width, height)
		return .Create_Target
	}

	format, is_srgb, ok := choose_offscreen_format(r)
	if !ok {
		log.error("renderer: no color format supports offscreen rendering")
		return .Create_Target
	}

	color, color_ok := create_image(
		r,
		width,
		height,
		format,
		{.COLOR_ATTACHMENT, .TRANSFER_SRC},
		{.COLOR},
	)
	if !color_ok {
		return .Create_Target
	}
	r.target.color = color

	r.target.config = {
		width   = width,
		height  = height,
		format  = format,
		is_srgb = is_srgb,
	}
	r.target.images = make([]vk.Image, 1, r.allocator)
	r.target.images[0] = color.image
	r.target.views = make([]vk.ImageView, 1, r.allocator)
	r.target.views[0] = color.view

	log.infof("renderer: offscreen target %vx%v, format %v", width, height, format)
	return .None
}

@(private)
choose_offscreen_format :: proc(r: ^Renderer) -> (format: vk.Format, is_srgb: bool, ok: bool) {
	for candidate in OFFSCREEN_FORMATS {
		properties: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(r.physical_device, candidate, &properties)
		features := properties.optimalTilingFeatures
		if .COLOR_ATTACHMENT not_in features || .TRANSFER_SRC not_in features {
			continue
		}
		return candidate, candidate == .R8G8B8A8_SRGB || candidate == .B8G8R8A8_SRGB, true
	}
	return .UNDEFINED, false, false
}
