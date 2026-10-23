#+vet explicit-allocators
package renderer

import "core:log"

import vk "vendor:vulkan"

Image :: struct {
	image:  vk.Image,
	memory: vk.DeviceMemory,
	view:   vk.ImageView,
}

create_image :: proc(
	r: ^Renderer,
	width, height: u32,
	format: vk.Format,
	usage: vk.ImageUsageFlags,
	aspect: vk.ImageAspectFlags,
) -> (
	result: Image,
	ok: bool,
) {
	info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		format = format,
		extent = {width, height, 1},
		mipLevels = 1,
		arrayLayers = 1,
		samples = {._1},
		tiling = .OPTIMAL,
		usage = usage,
		sharingMode = .EXCLUSIVE,
		initialLayout = .UNDEFINED,
	}
	if !check(vk.CreateImage(r.device, &info, nil, &result.image), "vkCreateImage") {
		return {}, false
	}

	requirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(r.device, result.image, &requirements)
	memory_type, found := find_memory_type(r, requirements.memoryTypeBits, {.DEVICE_LOCAL})
	if !found {
		log.error("renderer: no device-local memory type for the image")
		destroy_image(r, &result)
		return {}, false
	}
	allocate_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = requirements.size,
		memoryTypeIndex = memory_type,
	}
	if !check(vk.AllocateMemory(r.device, &allocate_info, nil, &result.memory), "vkAllocateMemory") {
		destroy_image(r, &result)
		return {}, false
	}
	if !check(vk.BindImageMemory(r.device, result.image, result.memory, 0), "vkBindImageMemory") {
		destroy_image(r, &result)
		return {}, false
	}

	view_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = result.image,
		viewType = .D2,
		format = format,
		subresourceRange = {aspectMask = aspect, levelCount = 1, layerCount = 1},
	}
	if !check(vk.CreateImageView(r.device, &view_info, nil, &result.view), "vkCreateImageView") {
		destroy_image(r, &result)
		return {}, false
	}
	return result, true
}

destroy_image :: proc(r: ^Renderer, image: ^Image) {
	if r.device == nil {
		return
	}
	if image.view != 0 {
		vk.DestroyImageView(r.device, image.view, nil)
		image.view = 0
	}
	if image.image != 0 {
		vk.DestroyImage(r.device, image.image, nil)
		image.image = 0
	}
	if image.memory != 0 {
		vk.FreeMemory(r.device, image.memory, nil)
		image.memory = 0
	}
}
