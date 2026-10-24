#+vet explicit-allocators
package renderer

import "core:log"
import "core:mem"

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

// Uploads one mip level and leaves the image in SHADER_READ_ONLY_OPTIMAL, ready
// for a combined image sampler.
upload_texture :: proc(
	r: ^Renderer,
	width, height: u32,
	format: vk.Format,
	pixels: []u8,
) -> (
	result: Image,
	ok: bool,
) {
	size := vk.DeviceSize(len(pixels))
	staging: vk.Buffer
	staging_memory: vk.DeviceMemory
	if !create_buffer(r, size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging, &staging_memory) {
		return {}, false
	}
	defer destroy_buffer(r, &staging, &staging_memory)

	mapped: rawptr
	if !check(vk.MapMemory(r.device, staging_memory, 0, size, {}, &mapped), "vkMapMemory") {
		return {}, false
	}
	mem.copy(mapped, raw_data(pixels), len(pixels))
	vk.UnmapMemory(r.device, staging_memory)

	result, ok = create_image(r, width, height, format, {.SAMPLED, .TRANSFER_DST}, {.COLOR})
	if !ok {
		return {}, false
	}

	command_buffer, command_ok := begin_immediate_command(r)
	if !command_ok {
		destroy_image(r, &result)
		return {}, false
	}
	defer free_immediate_command(r, command_buffer)

	image_barrier(
		command_buffer,
		result.image,
		COLOR_SUBRESOURCE,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		{.TOP_OF_PIPE},
		{.TRANSFER},
		{},
		{.TRANSFER_WRITE},
	)
	region := vk.BufferImageCopy {
		imageSubresource = {aspectMask = COLOR_SUBRESOURCE.aspectMask, layerCount = 1},
		imageExtent = {width, height, 1},
	}
	vk.CmdCopyBufferToImage(command_buffer, staging, result.image, .TRANSFER_DST_OPTIMAL, 1, &region)
	image_barrier(
		command_buffer,
		result.image,
		COLOR_SUBRESOURCE,
		.TRANSFER_DST_OPTIMAL,
		.SHADER_READ_ONLY_OPTIMAL,
		{.TRANSFER},
		{.FRAGMENT_SHADER},
		{.TRANSFER_WRITE},
		{.SHADER_READ},
	)

	if !end_immediate_command(r, command_buffer) {
		destroy_image(r, &result)
		return {}, false
	}
	return result, true
}

image_barrier :: proc(
	command_buffer: vk.CommandBuffer,
	image: vk.Image,
	subresource: vk.ImageSubresourceRange,
	old_layout, new_layout: vk.ImageLayout,
	src_stage, dst_stage: vk.PipelineStageFlags,
	src_access, dst_access: vk.AccessFlags,
) {
	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		srcAccessMask = src_access,
		dstAccessMask = dst_access,
		oldLayout = old_layout,
		newLayout = new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = subresource,
	}
	vk.CmdPipelineBarrier(command_buffer, src_stage, dst_stage, {}, 0, nil, 0, nil, 1, &barrier)
}
