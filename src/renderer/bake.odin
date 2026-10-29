#+vet explicit-allocators
#+vet !unused-procedures // the harness reads the report; the game binary does not
package renderer

import "core:fmt"
import "core:log"
import "core:os"
import "core:slice"
import "core:strings"

import "src:bake"
import vk "vendor:vulkan"

DEFAULT_BAKE_PATH :: "build/bake/arena.hbake"
INVALID_LIGHTMAP_SLOT :: u32(0xFFFFFFFF)

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
	mapped_boxes:   int    `json:"mapped_boxes"`,
	unmapped_boxes: int    `json:"unmapped_boxes"`,
	invalid_probes: int    `json:"invalid_probes"`,
	dilated_probes: int    `json:"dilated_probes"`,
	skipped_probes: int    `json:"skipped_probes"`,
	bake_ms:        u32    `json:"bake_ms"`,
	error:          string `json:"error,omitempty"`,
}

Bake_Volume_Uniform :: struct {
	min:           [3]f32,
	spacing:       f32,
	counts:        [3]u32,
	probe_grid:    u32,
	atlas_columns: u32,
	probe_count:   u32,
	_pad:          [2]u32,
}

#assert(size_of(Bake_Volume_Uniform) == 48)

Bake_Resources :: struct {
	status:         Bake_Status,
	path:           string,
	error:          string,
	data:           bake.Data,
	loaded:         bool,
	current_key:    u64,
	gpu_bytes:      int,
	mapped_boxes:   int,
	unmapped_boxes: int,
	dilated_probes: int,
	skipped_probes: int,

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
	states_bytes:      int,
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
		report.invalid_probes = int(r.bake.data.stats.invalid_probes)
		report.bake_ms = r.bake.data.stats.bake_ms
	}
	report.gpu_bytes = r.bake.gpu_bytes
	report.mapped_boxes = r.bake.mapped_boxes
	report.unmapped_boxes = r.bake.unmapped_boxes
	report.dilated_probes = r.bake.dilated_probes
	report.skipped_probes = r.bake.skipped_probes
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
	bake.destroy(&b.data, r.allocator)
	if b.path != "" {
		delete(b.path, r.allocator)
	}
	if b.error != "" {
		delete(b.error, r.allocator)
	}
	b^ = {}
}

@(private)
create_bake_resources :: proc(r: ^Renderer) -> bool {
	data := &r.bake.data
	if !format_supports(r, .R16G16B16A16_SFLOAT, {.SAMPLED_IMAGE_FILTER_LINEAR}) {
		log_bake_error(r, "the device cannot filter R16G16B16A16_SFLOAT")
		return false
	}
	if !format_supports(r, .R16G16_SFLOAT, {.SAMPLED_IMAGE_FILTER_LINEAR}) {
		log_bake_error(r, "the device cannot filter R16G16_SFLOAT")
		return false
	}

	r.bake.dilated_probes, r.bake.skipped_probes = dilate_probes(r)

	lightmap, lightmap_ok := upload_texture(
		r,
		data.header.atlas_width,
		data.header.atlas_height,
		.R16G16B16A16_SFLOAT,
		data.atlas,
	)
	if !lightmap_ok {
		return false
	}
	r.bake.lightmap = lightmap

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

	if !create_clamp_sampler(r, &r.bake.sampler) {
		return false
	}

	if !create_device_buffer(
		r,
		raw_data(data.faces),
		vk.DeviceSize(len(data.faces) * size_of(bake.Face)),
		{.STORAGE_BUFFER},
		&r.bake.faces_buffer,
		&r.bake.faces_memory,
	) {
		return false
	}
	r.bake.faces_bytes = len(data.faces) * size_of(bake.Face)
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
	r.bake.states_bytes = len(data.probe_states) * size_of(bake.Probe_State)

	volume := Bake_Volume_Uniform {
		min           = data.header.probe_min,
		spacing       = data.header.probe_spacing,
		counts        = data.header.probe_counts,
		probe_grid    = data.header.probe_texels,
		atlas_columns = data.header.probe_atlas_columns,
		probe_count   = data.header.probe_count,
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

// A slot is the index of the baked face list for one static box. Dynamic boxes
// and boxes absent from the artifact have no slot. Slots are written in
// canonical key order, so a search does not grow with the frame's box count.
bake_slot_for :: proc(r: ^Renderer, key: u64) -> (slot: u32, ok: bool) {
	if !r.bake.loaded || key == bake.NO_BOX_KEY {
		return INVALID_LIGHTMAP_SLOT, false
	}
	index, found := slice.binary_search_by(
		r.bake.data.slots,
		key,
		proc(entry: bake.Slot, key: u64) -> slice.Ordering {
			if entry.key < key {
				return .Less
			}
			if entry.key > key {
				return .Greater
			}
			return .Equal
		},
	)
	if !found {
		return INVALID_LIGHTMAP_SLOT, false
	}
	return u32(index), true
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
