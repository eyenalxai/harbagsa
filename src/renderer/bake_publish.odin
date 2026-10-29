#+vet explicit-allocators
#+vet !unused-procedures // the harness publishes and reloads through this API
package renderer

import "core:fmt"
import "core:strings"
import "core:time"

import "src:bake"
import vk "vendor:vulkan"

@(private)
destroy_bake_resources :: proc(r: ^Renderer) {
	b := &r.bake
	destroy_image(r, &b.lightmap)
	destroy_image(r, &b.probe_irradiance)
	destroy_image(r, &b.probe_moments)
	if r.device != nil && b.sampler != 0 {
		vk.DestroySampler(r.device, b.sampler, nil)
	}
	b.sampler = 0
	destroy_buffer(r, &b.faces_buffer, &b.faces_memory)
	destroy_buffer(r, &b.slots_buffer, &b.slots_memory)
	destroy_buffer(r, &b.states_buffer, &b.states_memory)
	destroy_buffer(r, &b.volume_buffer, &b.volume_memory)
	bake.destroy(&b.data, r.allocator)
	b.loaded = false
	b.gpu_bytes = 0
	b.faces_bytes = 0
	b.states_bytes = 0
	b.mapped_boxes = 0
	b.unmapped_boxes = 0
	b.dilated_probes = 0
	b.skipped_probes = 0
	b.build_ms = 0
	b.publish_ms = 0
}

// An explicit publish replaces the bound artifact with the bytes the caller
// built from the current static input. The bytes are consumed in every case.
publish_bake :: proc(r: ^Renderer, bytes: []u8, build_ms: u32) -> bool {
	data, load_error := bake.load(bytes)
	if load_error != .None {
		delete(bytes, r.allocator)
		set_bake_error(r, fmt.tprintf("publish: %s", bake.error_name(load_error)))
		return false
	}
	start := time.now()
	if r.device != nil {
		_ = vk.DeviceWaitIdle(r.device)
	}
	destroy_bake_resources(r)
	r.bake.data = data
	r.bake.loaded = true
	r.bake.status = .Stale
	r.bake.publish_ms = 0
	if !create_bake_resources(r) {
		if r.bake.status != .Failed {
			log_bake_error(r, "cannot create the published bake resources")
		}
		return false
	}
	r.bake.current_key = data.header.bake_key
	r.bake.status = .Current
	r.bake.build_ms = build_ms
	write_scene_bindings(r)
	r.bake.publish_ms = u32(time.duration_milliseconds(time.since(start)))
	reset_history(r, .Bake_Publish)
	return true
}

// Reload re-reads the configured path. It is the publish path for an artifact
// built by `make bake` while the process is running.
reload_bake :: proc(r: ^Renderer) -> bool {
	path := strings.clone(r.bake.path, r.allocator)
	defer delete(path, r.allocator)
	if r.device != nil {
		_ = vk.DeviceWaitIdle(r.device)
	}
	destroy_bake_resources(r)
	if !init_bake(r, path) {
		return false
	}
	write_scene_bindings(r)
	reset_history(r, .Bake_Publish)
	return true
}
