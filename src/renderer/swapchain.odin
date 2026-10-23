#+vet explicit-allocators
package renderer

import "core:log"

import vk "vendor:vulkan"

COLOR_SUBRESOURCE :: vk.ImageSubresourceRange{
	aspectMask = {.COLOR},
	levelCount = 1,
	layerCount = 1,
}

DEPTH_FORMAT :: vk.Format.D32_SFLOAT

DEPTH_SUBRESOURCE :: vk.ImageSubresourceRange {
	aspectMask = {.DEPTH},
	levelCount = 1,
	layerCount = 1,
}

create_platform_surface :: proc(r: ^Renderer) -> Error {
	if r.platform.create_surface == nil {
		log.error("renderer: no platform surface adapter")
		return .Platform
	}
	surface, ok := r.platform.create_surface(r.platform.user, r.instance)
	if !ok || surface == 0 {
		log.error("renderer: platform surface creation failed")
		return .Platform
	}
	r.target.surface = surface
	return .None
}

init_swapchain_target :: proc(r: ^Renderer) -> Error {
	if status := create_swapchain(r); status != .Ok {
		return .Create_Swapchain
	}
	return .None
}

create_swapchain :: proc(r: ^Renderer) -> Frame_Status {
	support, support_ok := query_swapchain_support(r.physical_device, r.target.surface, r.allocator)
	if !support_ok {
		log.error("renderer: could not query swapchain support")
		return .Fatal
	}
	defer delete(support.formats, r.allocator)

	format := choose_surface_format(support.formats)
	width, height := r.platform.pixel_size(r.platform.user)
	extent := choose_swapchain_extent(support.capabilities, width, height)
	if extent.width == 0 || extent.height == 0 {
		log.warnf("renderer: swapchain extent is zero (%vx%v)", extent.width, extent.height)
		return .Skipped
	}

	r.target.config = {
		width   = extent.width,
		height  = extent.height,
		format  = format.format,
		is_srgb = format.format == .B8G8R8A8_SRGB || format.format == .R8G8B8A8_SRGB,
	}

	image_count := support.capabilities.minImageCount + 1
	if support.capabilities.maxImageCount > 0 && image_count > support.capabilities.maxImageCount {
		image_count = support.capabilities.maxImageCount
	}

	create_info := vk.SwapchainCreateInfoKHR{
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = r.target.surface,
		minImageCount    = image_count,
		imageFormat      = format.format,
		imageColorSpace  = format.colorSpace,
		imageExtent      = extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT, .TRANSFER_SRC},
		preTransform     = support.capabilities.currentTransform,
		compositeAlpha   = choose_composite_alpha(support.capabilities.supportedCompositeAlpha),
		presentMode      = .FIFO,
		clipped          = true,
	}
	if r.graphics_family != r.present_family {
		create_info.imageSharingMode = .CONCURRENT
		create_info.queueFamilyIndexCount = 2
		create_info.pQueueFamilyIndices = raw_data([]u32{r.graphics_family, r.present_family})
	} else {
		create_info.imageSharingMode = .EXCLUSIVE
	}

	if !check(vk.CreateSwapchainKHR(r.device, &create_info, nil, &r.target.swapchain), "vkCreateSwapchainKHR") {
		return .Fatal
	}

	image_count_actual: u32
	if !check(
		vk.GetSwapchainImagesKHR(r.device, r.target.swapchain, &image_count_actual, nil),
		"vkGetSwapchainImagesKHR",
	) {
		return .Fatal
	}
	r.target.images = make([]vk.Image, image_count_actual, r.allocator)
	if !check(
		vk.GetSwapchainImagesKHR(r.device, r.target.swapchain, &image_count_actual, raw_data(r.target.images)),
		"vkGetSwapchainImagesKHR",
	) {
		return .Fatal
	}

	r.target.views = make([]vk.ImageView, image_count_actual, r.allocator)
	for image, i in r.target.images {
		view_info := vk.ImageViewCreateInfo{
			sType            = .IMAGE_VIEW_CREATE_INFO,
			image            = image,
			viewType         = .D2,
			format           = format.format,
			subresourceRange = COLOR_SUBRESOURCE,
		}
		if !check(vk.CreateImageView(r.device, &view_info, nil, &r.target.views[i]), "vkCreateImageView") {
			return .Fatal
		}
	}

	if !create_depth_resources(r) {
		log.error("renderer: could not create depth resources")
		return .Fatal
	}
	if !create_readback(r, extent.width, extent.height) {
		log.error("renderer: could not create the capture readback buffer")
		return .Fatal
	}

	log.infof(
		"renderer: swapchain %vx%v with %d images, format %v",
		extent.width,
		extent.height,
		image_count_actual,
		format.format,
	)
	return .Ok
}

destroy_swapchain_images :: proc(r: ^Renderer) {
	destroy_depth_resources(r)

	if r.device != nil {
		for view in r.target.views {
			if view != 0 {
				vk.DestroyImageView(r.device, view, nil)
			}
		}
		if r.target.swapchain != 0 {
			vk.DestroySwapchainKHR(r.device, r.target.swapchain, nil)
			r.target.swapchain = 0
		}
	}
}

recreate_swapchain :: proc(r: ^Renderer) -> Frame_Status {
	width, height := r.platform.pixel_size(r.platform.user)
	if width == 0 || height == 0 {
		r.target.dirty = true
		return .Skipped
	}

	if !check(vk.DeviceWaitIdle(r.device), "vkDeviceWaitIdle") {
		return .Fatal
	}
	destroy_swapchain_images(r)
	destroy_readback(r)
	delete_target_slices(r)
	if status := create_swapchain(r); status != .Ok {
		return status
	}
	if r.scene.pipeline != 0 && r.scene.pipeline_format != r.target.config.format {
		destroy_pipeline_pair(r, &r.scene.pipeline, &r.scene.pipeline_layout)
		if !create_pipeline(r) {
			return .Fatal
		}
	}
	if r.overlay.pipeline_format != r.target.config.format {
		destroy_overlay_pipelines(r)
		if !create_overlay_pipelines(r) {
			return .Fatal
		}
	}
	r.target.dirty = false

	return .Ok
}

create_depth_resources :: proc(r: ^Renderer) -> bool {
	destroy_depth_resources(r)

	image_count := len(r.target.images)
	if image_count == 0 {
		log.error("renderer: cannot create depth resources without swapchain images")
		return false
	}

	r.target.depth = make([]Image, image_count, r.allocator)

	for i in 0 ..< image_count {
		image, ok := create_image(
			r,
			r.target.config.width,
			r.target.config.height,
			DEPTH_FORMAT,
			{.DEPTH_STENCIL_ATTACHMENT},
			{.DEPTH},
		)
		if !ok {
			return false
		}
		r.target.depth[i] = image
	}

	return true
}

destroy_depth_resources :: proc(r: ^Renderer) {
	for &image in r.target.depth {
		destroy_image(r, &image)
	}
	if r.target.depth != nil {
		delete(r.target.depth, r.allocator)
		r.target.depth = nil
	}
}
