#+vet explicit-allocators
#+vet !unused-procedures // the harness reads the report; the game binary does not
package renderer

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

import "src:bake"
import vk "vendor:vulkan"

DEFAULT_BAKE_PATH :: "build/bake/arena.hbake"

Bake_Status :: enum u8 {
	Missing,
	Stale,
	Current,
	Failed,
}

bake_status_name :: proc(status: Bake_Status) -> string {
	switch status {
	case .Missing:
		return "missing"
	case .Stale:
		return "stale"
	case .Current:
		return "current"
	case .Failed:
		return "failed"
	}
	return "missing"
}

Bake_Report :: struct {
	status:         string `json:"status"`,
	key:            u64    `json:"key"`,
	artifact_key:   u64    `json:"artifact_key"`,
	format_version: u16    `json:"format_version"`,
	tool_version:   u32    `json:"tool_version"`,
	atlas_width:    u32    `json:"atlas_width"`,
	atlas_height:   u32    `json:"atlas_height"`,
	texels:         int    `json:"texels"`,
	faces:          int    `json:"faces"`,
	slots:          int    `json:"slots"`,
	probes:         int    `json:"probes"`,
	probe_spacing:  f32    `json:"probe_spacing"`,
	invalid_probes: u32    `json:"invalid_probes"`,
	probe_missing:  int    `json:"probe_missing"`,
	artifact_bytes: int    `json:"artifact_bytes"`,
	gpu_bytes:      int    `json:"gpu_bytes"`,
	bake_ms:        u32    `json:"bake_ms"`,
	error:          string `json:"error,omitempty"`,
}

Bake_Volume_Uniform :: struct {
	min:           [3]f32,
	spacing:       f32,
	counts:        [3]u32,
	probe_texels:  u32,
	atlas_columns: u32,
	probe_count:   u32,
	atlas_width:   u32,
	atlas_height:  u32,
}

#assert(size_of(Bake_Volume_Uniform) == 48)

Bake_Resources :: struct {
	status:      Bake_Status,
	path:        string,
	error:       string,
	data:        bake.Data,
	loaded:      bool,
	current_key:   u64,
	bake_ms:       u32,
	gpu_bytes:     int,
	probe_missing: int,
	slot_lookup:   map[u64]u32,

	lightmap:          Image,
	probe_irradiance:  Image,
	probe_moments:     Image,
	sampler:           vk.Sampler,
	faces_buffer:      vk.Buffer,
	faces_memory:      vk.DeviceMemory,
	faces_bytes:       int,
	states_bytes:      int,
	slots_buffer:      vk.Buffer,
	slots_memory:      vk.DeviceMemory,
	states_buffer:     vk.Buffer,
	states_memory:     vk.DeviceMemory,
	volume_buffer:     vk.Buffer,
	volume_memory:     vk.DeviceMemory,
}

init_bake :: proc(r: ^Renderer, path: string) -> bool {
	r.bake.path = strings.clone(DEFAULT_BAKE_PATH, r.allocator)
	if path != "" {
		delete(r.bake.path, r.allocator)
		r.bake.path = strings.clone(path, r.allocator)
	}
	r.bake.status = .Missing

	bytes, read_error := os.read_entire_file(r.bake.path, r.allocator)
	if read_error != nil {
		if general, ok := read_error.(os.General_Error); ok && general == .Not_Exist {
			return create_bake_placeholder(r)
		}
		r.bake.status = .Failed
		r.bake.error = fmt.aprintf(
			"cannot read %s: %v",
			r.bake.path,
			read_error,
			allocator = r.allocator,
		)
		return create_bake_placeholder(r)
	}

	data, load_error := bake.load(bytes)
	if load_error != .None {
		delete(bytes, r.allocator)
		r.bake.status = .Failed
		r.bake.error = fmt.aprintf(
			"%s: %s",
			r.bake.path,
			bake.error_name(load_error),
			allocator = r.allocator,
		)
		log.errorf("renderer: %s", r.bake.error)
		return create_bake_placeholder(r)
	}
	r.bake.data = data
	r.bake.loaded = true
	r.bake.status = .Stale
	if !create_bake_resources(r, &r.bake) {
		if r.bake.status != .Failed {
			log_bake_error(r, "cannot create the bake resources")
		}
		return false
	}
	return true
}

bake_key :: proc(r: ^Renderer, static: bake.Static) -> u64 {
	quality := bake.DEFAULT_QUALITY
	if r.bake.loaded {
		quality = r.bake.data.quality
	}
	return bake.key(static, quality)
}

// The harness reads state without drawing a frame, so it refreshes the key from
// the current static input before it reports. The renderer stays the owner of
// the applied status.
refresh_bake :: proc(r: ^Renderer, static: bake.Static) {
	update_bake(r, bake_key(r, static))
}

update_bake :: proc(r: ^Renderer, key: u64) {
	r.bake.current_key = key
	if !r.bake.loaded || r.bake.status == .Failed {
		return
	}
	r.bake.status = r.bake.data.header.bake_key == key ? .Current : .Stale
}

// A static box owns a slot only when the loaded artifact baked its key. A
// missing slot stays on the direct path; it never borrows another tile.
bake_box_slot :: proc(r: ^Renderer, slot: bake.Box_Slot) -> (index: u32, ok: bool) {
	if !slot.has_slot || !r.bake.loaded {
		return 0, false
	}
	index, ok = r.bake.slot_lookup[slot.key]
	return
}

bake_report :: proc(r: ^Renderer) -> Bake_Report {
	report := Bake_Report {
		status = bake_status_name(r.bake.status),
		key    = r.bake.current_key,
		error  = r.bake.error,
	}
	if r.bake.loaded {
		header := r.bake.data.header
		report.artifact_key = header.bake_key
		report.format_version = header.format_version
		report.tool_version = header.tool_version
		report.atlas_width = header.atlas_width
		report.atlas_height = header.atlas_height
		report.texels = int(header.atlas_width) * int(header.atlas_height)
		report.faces = int(header.face_count)
		report.slots = int(header.slot_count)
		report.probes = int(header.probe_count)
		report.probe_spacing = header.probe_spacing
		report.invalid_probes = r.bake.data.stats.invalid_probes
		report.artifact_bytes = len(r.bake.data.bytes)
		report.bake_ms = r.bake.data.stats.bake_ms
	}
	// The artifact stores zero so the bytes stay deterministic. An explicit
	// publish carries the measured time in memory.
	if r.bake.bake_ms != 0 {
		report.bake_ms = r.bake.bake_ms
	}
	report.gpu_bytes = r.bake.gpu_bytes
	report.probe_missing = r.bake.probe_missing
	return report
}

destroy_bake :: proc(r: ^Renderer) {
	b := &r.bake
	destroy_bake_resources(r, b)
	bake.destroy(&b.data, r.allocator)
	if b.path != "" {
		delete(b.path, r.allocator)
	}
	if b.error != "" {
		delete(b.error, r.allocator)
	}
	b^ = {}
}
