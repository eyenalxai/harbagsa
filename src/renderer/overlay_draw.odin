#+vet explicit-allocators
package renderer

import vk "vendor:vulkan"

overlay_draw :: proc(r: ^Renderer, command_buffer: vk.CommandBuffer, pass: ^Pass) {
	record_overlay(r, command_buffer)
}
