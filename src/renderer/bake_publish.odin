#+vet explicit-allocators
#+vet !unused-procedures // the harness publishes and reloads through this API
package renderer

import "core:fmt"
import "core:os"
import "core:time"

import "src:bake"
import vk "vendor:vulkan"

@(private)
destroy_bake_resources :: proc(r: ^Renderer, b: ^Bake_Resources) {
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
	b.build_threads = 0
	b.publish_ms = 0
	b.failed = false
}

// A replacement is built into its own resource set. A parse or device failure
// leaves the bound artifact in place and reports failed until the next success.
@(private)
replace_bake :: proc(
	r: ^Renderer,
	bytes: []u8,
	build_ms: u32,
	build_threads: int,
	cause: string,
) -> bool {
	start := time.now()
	data, load_error := bake.load(bytes)
	if load_error != .None {
		delete(bytes, r.allocator)
		set_bake_error(r, fmt.tprintf("%s: %s", cause, bake.error_name(load_error)))
		return false
	}
	replacement := Bake_Resources {
		data    = data,
		loaded  = true,
		status  = .Current,
		build_ms = build_ms,
		build_threads = build_threads,
	}
	if !create_bake_resources(r, &replacement.data, &replacement) {
		destroy_bake_resources(r, &replacement)
		set_bake_error(r, fmt.tprintf("%s: cannot create the bake resources", cause))
		return false
	}
	if r.device != nil {
		_ = vk.DeviceWaitIdle(r.device)
	}
	old := r.bake
	r.bake = replacement
	r.bake.path = old.path
	r.bake.current_key = data.header.bake_key
	r.bake.publish_ms = u32(time.duration_milliseconds(time.since(start)))
	destroy_bake_resources(r, &old)
	if old.error != "" {
		delete(old.error, r.allocator)
	}
	write_scene_bindings(r)
	reset_history(r, .Bake_Publish)
	return true
}

// An explicit publish replaces the bound artifact with the bytes the caller
// built from the current static input. The bytes are consumed in every case.
publish_bake :: proc(
	r: ^Renderer,
	bytes: []u8,
	build_ms: u32,
	build_threads: int,
) -> bool {
	return replace_bake(r, bytes, build_ms, build_threads, "publish")
}

// Reload re-reads the configured path. It is the publish path for an artifact
// built by `make bake` while the process is running.
reload_bake :: proc(r: ^Renderer) -> bool {
	bytes, read_error := os.read_entire_file(r.bake.path, r.allocator)
	if read_error != nil {
		set_bake_error(r, fmt.tprintf("reload: cannot read the artifact: %v", read_error))
		return false
	}
	return replace_bake(r, bytes, 0, 0, "reload")
}
