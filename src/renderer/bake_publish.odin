#+vet explicit-allocators
#+vet !unused-procedures // the harness publishes through this path
package renderer

import "core:fmt"
import "core:strings"

import "src:bake"
import vk "vendor:vulkan"

// Publish replaces the bound indirect data without restarting the renderer. The
// bytes must come from the renderer allocator; this proc owns them on every
// path. A failed publish leaves the old artifact bound and the failure visible.
publish_bake :: proc(r: ^Renderer, bytes: []u8, bake_ms: u32) -> (ok: bool, err: string) {
	data, load_error := bake.load(bytes)
	if load_error != .None {
		delete(bytes, r.allocator)
		return false, fmt.aprintf(
			"bake: %s",
			bake.error_name(load_error),
			allocator = context.allocator,
		)
	}

	next := Bake_Resources {
		data        = data,
		loaded      = true,
		status      = .Current,
		current_key = data.header.bake_key,
		bake_ms     = bake_ms,
	}
	if !create_bake_resources(r, &next) {
		destroy_bake_resources(r, &next)
		bake.destroy(&next.data, r.allocator)
		if r.bake.status != .Failed {
			log_bake_error(r, "cannot create the bake resources")
		}
		message := r.bake.error
		if message == "" {
			message = "cannot create the bake resources"
		}
		return false, strings.clone(message, context.allocator)
	}

	// A previous frame may still read the old images and buffers.
	if r.device != nil {
		_ = vk.DeviceWaitIdle(r.device)
	}
	destroy_bake_resources(r, &r.bake)
	bake.destroy(&r.bake.data, r.allocator)

	path := r.bake.path
	previous_error := r.bake.error
	r.bake = next
	r.bake.path = path
	if previous_error != "" {
		delete(previous_error, r.allocator)
	}
	write_scene_bindings(r)
	return true, ""
}
