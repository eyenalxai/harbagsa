#+vet explicit-allocators
#+vet !unused-procedures // the harness reads captures; the game binary does not
package renderer

import "core:mem"

import vk "vendor:vulkan"

record_capture_copy :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, image_index: u32) -> bool {
	if r.target.readback.buffer == 0 || r.target.readback.size == 0 {
		return false
	}
	to_transfer := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
		dstAccessMask = {.TRANSFER_READ},
		oldLayout = .COLOR_ATTACHMENT_OPTIMAL,
		newLayout = .TRANSFER_SRC_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = r.target.images[image_index],
		subresourceRange = COLOR_SUBRESOURCE,
	}
	vk.CmdPipelineBarrier(
		command_buffer,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.TRANSFER},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&to_transfer,
	)

	region := vk.BufferImageCopy {
		bufferOffset = 0,
		bufferRowLength = 0,
		bufferImageHeight = 0,
		imageSubresource = {
			aspectMask = {.COLOR},
			mipLevel = 0,
			baseArrayLayer = 0,
			layerCount = 1,
		},
		imageOffset = {0, 0, 0},
		imageExtent = {r.target.config.width, r.target.config.height, 1},
	}
	vk.CmdCopyImageToBuffer(
		command_buffer,
		r.target.images[image_index],
		.TRANSFER_SRC_OPTIMAL,
		r.target.readback.buffer,
		1,
		&region,
	)
	return true
}

read_capture :: proc(r: ^Renderer) -> (pixels: []u8, width, height: u32, ok: bool) {
	if r.target.readback.mapped == nil || r.target.readback.size == 0 {
		return nil, 0, 0, false
	}
	size := int(r.target.readback.size)
	mem.copy(raw_data(r.target.readback.pixels), r.target.readback.mapped, size)
	if r.target.config.format == .B8G8R8A8_SRGB ||
	   r.target.config.format == .B8G8R8A8_UNORM {
		for i := 0; i + 3 < size; i += 4 {
			r.target.readback.pixels[i], r.target.readback.pixels[i + 2] =
				r.target.readback.pixels[i + 2], r.target.readback.pixels[i]
		}
	}
	return r.target.readback.pixels, r.target.config.width, r.target.config.height, true
}
