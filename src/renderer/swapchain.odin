#+vet explicit-allocators
package renderer

import "core:log"

import "src:platform"
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

create_swapchain :: proc(r: ^Renderer) -> Frame_Status {
	support, support_ok := query_swapchain_support(r.physical_device, r.surface, r.allocator)
	if !support_ok {
		log.error("renderer: could not query swapchain support")
		return .Fatal
	}
	defer delete(support.formats, r.allocator)

	format := choose_surface_format(support.formats)
	extent := choose_swapchain_extent(support.capabilities, r.window)
	if extent.width == 0 || extent.height == 0 {
		log.warnf("renderer: swapchain extent is zero (%vx%v)", extent.width, extent.height)
		return .Skipped
	}

	r.swapchain_format = format.format
	r.swapchain_extent = extent
	r.swapchain_is_srgb = format.format == .B8G8R8A8_SRGB || format.format == .R8G8B8A8_SRGB

	image_count := support.capabilities.minImageCount + 1
	if support.capabilities.maxImageCount > 0 && image_count > support.capabilities.maxImageCount {
		image_count = support.capabilities.maxImageCount
	}

	create_info := vk.SwapchainCreateInfoKHR{
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = r.surface,
		minImageCount    = image_count,
		imageFormat      = format.format,
		imageColorSpace  = format.colorSpace,
		imageExtent      = extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT},
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

	if !check(vk.CreateSwapchainKHR(r.device, &create_info, nil, &r.swapchain), "vkCreateSwapchainKHR") {
		return .Fatal
	}

	image_count_actual: u32
	if !check(
		vk.GetSwapchainImagesKHR(r.device, r.swapchain, &image_count_actual, nil),
		"vkGetSwapchainImagesKHR",
	) {
		return .Fatal
	}
	r.swapchain_images = make([]vk.Image, image_count_actual, r.allocator)
	if !check(
		vk.GetSwapchainImagesKHR(r.device, r.swapchain, &image_count_actual, raw_data(r.swapchain_images)),
		"vkGetSwapchainImagesKHR",
	) {
		return .Fatal
	}

	r.swapchain_views = make([]vk.ImageView, image_count_actual, r.allocator)
	for image, i in r.swapchain_images {
		view_info := vk.ImageViewCreateInfo{
			sType            = .IMAGE_VIEW_CREATE_INFO,
			image            = image,
			viewType         = .D2,
			format           = format.format,
			subresourceRange = COLOR_SUBRESOURCE,
		}
		if !check(vk.CreateImageView(r.device, &view_info, nil, &r.swapchain_views[i]), "vkCreateImageView") {
			return .Fatal
		}
	}

	if !create_depth_resources(r) {
		log.error("renderer: could not create depth resources")
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

destroy_swapchain :: proc(r: ^Renderer) {
	destroy_depth_resources(r)

	if r.device != nil {
		for view in r.swapchain_views {
			if view != 0 {
				vk.DestroyImageView(r.device, view, nil)
			}
		}
		if r.swapchain != 0 {
			vk.DestroySwapchainKHR(r.device, r.swapchain, nil)
			r.swapchain = 0
		}
	}

	if r.swapchain_views != nil {
		delete(r.swapchain_views, r.allocator)
		r.swapchain_views = nil
	}
	if r.swapchain_images != nil {
		delete(r.swapchain_images, r.allocator)
		r.swapchain_images = nil
	}
}

recreate_swapchain :: proc(r: ^Renderer) -> Frame_Status {
	width, height := platform.pixel_size(r.window)
	if width == 0 || height == 0 {
		r.swapchain_dirty = true
		return .Skipped
	}

	if !check(vk.DeviceWaitIdle(r.device), "vkDeviceWaitIdle") {
		return .Fatal
	}
	destroy_swapchain(r)
	if status := create_swapchain(r); status != .Ok {
		return status
	}
	if r.scene.pipeline != 0 && r.scene.pipeline_format != r.swapchain_format {
		destroy_pipeline_pair(r, &r.scene.pipeline, &r.scene.pipeline_layout)
		if !create_pipeline(r) {
			return .Fatal
		}
	}
	if r.overlay.pipeline_format != .UNDEFINED && r.overlay.pipeline_format != r.swapchain_format {
		destroy_overlay_pipelines(r)
		if !create_overlay_pipelines(r) {
			return .Fatal
		}
	}
	r.swapchain_dirty = false

	return .Ok
}

create_depth_resources :: proc(r: ^Renderer) -> bool {
	destroy_depth_resources(r)

	image_count := len(r.swapchain_images)
	if image_count == 0 {
		log.error("renderer: cannot create depth resources without swapchain images")
		return false
	}

	r.scene.depth_images = make([]vk.Image, image_count, r.allocator)
	r.scene.depth_memory = make([]vk.DeviceMemory, image_count, r.allocator)
	r.scene.depth_views = make([]vk.ImageView, image_count, r.allocator)

	for i in 0 ..< image_count {
		image_info := vk.ImageCreateInfo {
			sType = .IMAGE_CREATE_INFO,
			imageType = .D2,
			format = DEPTH_FORMAT,
			extent = {r.swapchain_extent.width, r.swapchain_extent.height, 1},
			mipLevels = 1,
			arrayLayers = 1,
			samples = {._1},
			tiling = .OPTIMAL,
			usage = {.DEPTH_STENCIL_ATTACHMENT},
			sharingMode = .EXCLUSIVE,
			initialLayout = .UNDEFINED,
		}
		if !check(vk.CreateImage(r.device, &image_info, nil, &r.scene.depth_images[i]), "vkCreateImage") {
			return false
		}

		requirements: vk.MemoryRequirements
		vk.GetImageMemoryRequirements(r.device, r.scene.depth_images[i], &requirements)
		memory_type, found := find_memory_type(r, requirements.memoryTypeBits, {.DEVICE_LOCAL})
		if !found {
			log.error("renderer: no device-local memory type for the depth image")
			return false
		}
		allocate_info := vk.MemoryAllocateInfo {
			sType = .MEMORY_ALLOCATE_INFO,
			allocationSize = requirements.size,
			memoryTypeIndex = memory_type,
		}
		if !check(
			vk.AllocateMemory(r.device, &allocate_info, nil, &r.scene.depth_memory[i]),
			"vkAllocateMemory",
		) {
			return false
		}
		if !check(
			vk.BindImageMemory(r.device, r.scene.depth_images[i], r.scene.depth_memory[i], 0),
			"vkBindImageMemory",
		) {
			return false
		}

		view_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = r.scene.depth_images[i],
			viewType = .D2,
			format = DEPTH_FORMAT,
			subresourceRange = DEPTH_SUBRESOURCE,
		}
		if !check(vk.CreateImageView(r.device, &view_info, nil, &r.scene.depth_views[i]), "vkCreateImageView") {
			return false
		}
	}

	return true
}

destroy_depth_resources :: proc(r: ^Renderer) {
	if r.device != nil {
		for &view in r.scene.depth_views {
			if view != 0 {
				vk.DestroyImageView(r.device, view, nil)
				view = 0
			}
		}
		for &image in r.scene.depth_images {
			if image != 0 {
				vk.DestroyImage(r.device, image, nil)
				image = 0
			}
		}
		for &memory in r.scene.depth_memory {
			if memory != 0 {
				vk.FreeMemory(r.device, memory, nil)
				memory = 0
			}
		}
	}

	if r.scene.depth_views != nil {
		delete(r.scene.depth_views, r.allocator)
		r.scene.depth_views = nil
	}
	if r.scene.depth_images != nil {
		delete(r.scene.depth_images, r.allocator)
		r.scene.depth_images = nil
	}
	if r.scene.depth_memory != nil {
		delete(r.scene.depth_memory, r.allocator)
		r.scene.depth_memory = nil
	}
}
