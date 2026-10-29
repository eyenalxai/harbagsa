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
	current_key: u64,
	gpu_bytes:   int,
	slot_lookup: map[u64]u32,

	lightmap:          Image,
	probe_irradiance:  Image,
	probe_moments:     Image,
	sampler:           vk.Sampler,
	faces_buffer:      vk.Buffer,
	faces_memory:      vk.DeviceMemory,
	faces_bytes:       int,
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
	if !create_bake_resources(r) {
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

update_bake :: proc(r: ^Renderer, key: u64) {
	r.bake.current_key = key
	if !r.bake.loaded {
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
		report.artifact_bytes = len(r.bake.data.bytes)
		report.bake_ms = r.bake.data.stats.bake_ms
	}
	report.gpu_bytes = r.bake.gpu_bytes
	return report
}

destroy_bake :: proc(r: ^Renderer) {
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
	if b.slot_lookup != nil {
		delete(b.slot_lookup)
	}
	bake.destroy(&b.data, r.allocator)
	if b.path != "" {
		delete(b.path, r.allocator)
	}
	if b.error != "" {
		delete(b.error, r.allocator)
	}
	b^ = {}
}

// The lightmap image, the face rects, and the shared sampler are one unit. The
// placeholder and the loaded artifact use the same path so a missing bake
// cannot drift from a real one.
@(private)
create_bake_lightmap :: proc(
	r: ^Renderer,
	width, height: u32,
	format: vk.Format,
	atlas: []u8,
	faces: []bake.Face,
) -> bool {
	if !format_supports(r, format, {.SAMPLED_IMAGE_FILTER_LINEAR}) {
		log_bake_error(r, "the device cannot filter the lightmap format")
		return false
	}
	lightmap, lightmap_ok := upload_texture(r, width, height, format, atlas)
	if !lightmap_ok {
		return false
	}
	r.bake.lightmap = lightmap
	if !create_device_buffer(
		r,
		raw_data(faces),
		vk.DeviceSize(len(faces) * size_of(bake.Face)),
		{.STORAGE_BUFFER},
		&r.bake.faces_buffer,
		&r.bake.faces_memory,
	) {
		return false
	}
	r.bake.faces_bytes = len(faces) * size_of(bake.Face)
	return create_clamp_sampler(r, &r.bake.sampler)
}

@(private)
create_bake_placeholder :: proc(r: ^Renderer) -> bool {
	// A descriptor set must name an image and a storage buffer even when no bake
	// is loaded. Nothing samples them: every object's weight is zero while the
	// status reports missing or failed. The placeholder format is mandatory and
	// does not need the float lightmap support.
	zero := [4]u8{}
	faces := [1]bake.Face{}
	return create_bake_lightmap(r, 1, 1, .R8G8B8A8_UNORM, zero[:], faces[:])
}

@(private)
create_bake_resources :: proc(r: ^Renderer) -> bool {
	data := &r.bake.data
	if !format_supports(r, .R16G16_SFLOAT, {.SAMPLED_IMAGE_FILTER_LINEAR}) {
		log_bake_error(r, "the device cannot filter R16G16_SFLOAT")
		return false
	}
	if !create_bake_lightmap(
		r,
		data.header.atlas_width,
		data.header.atlas_height,
		.R16G16B16A16_SFLOAT,
		data.atlas,
		data.faces,
	) {
		return false
	}

	r.bake.slot_lookup = make(map[u64]u32, len(data.slots), r.allocator)
	for slot, index in data.slots {
		r.bake.slot_lookup[slot.key] = u32(index)
	}

	irradiance, irradiance_ok := upload_texture(
		r,
		data.probe_atlas_width,
		data.probe_atlas_height,
		.R16G16B16A16_SFLOAT,
		data.probe_irradiance,
	)
	if !irradiance_ok {
		return false
	}
	r.bake.probe_irradiance = irradiance

	moments, moments_ok := upload_texture(
		r,
		data.probe_atlas_width,
		data.probe_atlas_height,
		.R16G16_SFLOAT,
		data.probe_moments,
	)
	if !moments_ok {
		return false
	}
	r.bake.probe_moments = moments

	if !create_device_buffer(
		r,
		raw_data(data.slots),
		vk.DeviceSize(len(data.slots) * size_of(bake.Slot)),
		{.STORAGE_BUFFER},
		&r.bake.slots_buffer,
		&r.bake.slots_memory,
	) {
		return false
	}
	if !create_device_buffer(
		r,
		raw_data(data.probe_states),
		vk.DeviceSize(len(data.probe_states) * size_of(bake.Probe_State)),
		{.STORAGE_BUFFER},
		&r.bake.states_buffer,
		&r.bake.states_memory,
	) {
		return false
	}

	volume := Bake_Volume_Uniform {
		min           = data.header.probe_min,
		spacing       = data.header.probe_spacing,
		counts        = data.header.probe_counts,
		probe_texels  = data.header.probe_texels,
		atlas_columns = data.header.probe_atlas_columns,
		probe_count   = data.header.probe_count,
		atlas_width   = data.probe_atlas_width,
		atlas_height  = data.probe_atlas_height,
	}
	if !create_device_buffer(
		r,
		&volume,
		vk.DeviceSize(size_of(Bake_Volume_Uniform)),
		{.UNIFORM_BUFFER},
		&r.bake.volume_buffer,
		&r.bake.volume_memory,
	) {
		return false
	}

	r.bake.gpu_bytes = len(data.atlas) + len(data.probe_irradiance) + len(data.probe_moments)
	r.bake.gpu_bytes += len(data.faces) * size_of(bake.Face)
	r.bake.gpu_bytes += len(data.slots) * size_of(bake.Slot)
	r.bake.gpu_bytes += len(data.probe_states) * size_of(bake.Probe_State)
	r.bake.gpu_bytes += size_of(Bake_Volume_Uniform)
	return true
}

@(private)
log_bake_error :: proc(r: ^Renderer, message: string) {
	r.bake.status = .Failed
	if r.bake.error != "" {
		delete(r.bake.error, r.allocator)
	}
	r.bake.error = fmt.aprintf("%s: %s", r.bake.path, message, allocator = r.allocator)
	log.errorf("renderer: %s", r.bake.error)
}
