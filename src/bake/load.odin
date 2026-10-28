#+vet explicit-allocators
#+vet !unused-procedures // the renderer loads the artifact and reports the error
package bake

import "core:math"
import "core:mem"

import "src:digest"

// `load` takes ownership only on success. A caller that gets an error still
// owns `bytes` and must free it.
load :: proc(bytes: []u8) -> (data: Data, err: Error) {
	if len(bytes) < size_of(Header) {
		return {}, .Header
	}
	header: Header
	if !read_value(bytes, 0, &header) {
		return {}, .Header
	}
	if header.magic != MAGIC {
		return {}, .Magic
	}
	if header.format_version != FORMAT_VERSION {
		return {}, .Version
	}
	if header.header_bytes != u16(size_of(Header)) || header.flags != 0 {
		return {}, .Header
	}
	if header.atlas_format != u32(Atlas_Format.RGBA16F) {
		return {}, .Atlas_Format
	}
	if header.section_count != u32(SECTION_KIND_COUNT) {
		return {}, .Section_Table
	}
	table_bytes := u64(header.section_count) * u64(size_of(Section))
	if header.section_table_offset < u64(size_of(Header)) ||
	   header.section_table_offset > u64(len(bytes)) ||
	   table_bytes > u64(len(bytes)) - header.section_table_offset {
		return {}, .Section_Table
	}

	sections: [SECTION_KIND_COUNT]Section
	present: [SECTION_KIND_COUNT]bool
	for index in 0 ..< SECTION_KIND_COUNT {
		offset := header.section_table_offset + u64(index) * u64(size_of(Section))
		section: Section
		if !read_value(bytes, offset, &section) {
			return {}, .Section_Table
		}
		kind_index := int(section.kind) - 1
		if kind_index < 0 || kind_index >= SECTION_KIND_COUNT || present[kind_index] {
			return {}, .Section_Table
		}
		if section.offset % 16 != 0 ||
		   section.offset > u64(len(bytes)) ||
		   section.size > u64(len(bytes)) - section.offset {
			return {}, .Section_Bounds
		}
		sections[kind_index] = section
		present[kind_index] = true
	}

	quality_section := sections[int(Section_Kind.Quality) - 1]
	if !check_typed_section(quality_section, size_of(Quality), 1) {
		return {}, .Section_Size
	}
	quality: Quality
	if !read_value(bytes, quality_section.offset, &quality) {
		return {}, .Section_Size
	}
	if !quality_valid(quality) ||
	   quality.atlas_size != header.atlas_width ||
	   header.atlas_width != header.atlas_height ||
	   quality.probe_texels != header.probe_texels {
		return {}, .Quality
	}
	if header.atlas_width > MAX_ATLAS_DIM {
		return {}, .Quality
	}

	stats_section := sections[int(Section_Kind.Stats) - 1]
	if !check_typed_section(stats_section, size_of(Stats), 1) {
		return {}, .Section_Size
	}
	stats: Stats
	if !read_value(bytes, stats_section.offset, &stats) {
		return {}, .Section_Size
	}

	if header.face_count == 0 || header.slot_count == 0 {
		return {}, .Layout
	}
	if u64(header.slot_count) * 6 != u64(header.face_count) {
		return {}, .Layout
	}

	counts := header.probe_counts
	if counts.x == 0 || counts.y == 0 || counts.z == 0 {
		return {}, .Layout
	}
	probe_count := u64(counts.x) * u64(counts.y) * u64(counts.z)
	if probe_count != u64(header.probe_count) || probe_count > u64(MAX_PROBE_COUNT) {
		return {}, .Layout
	}
	if header.probe_texels != PROBE_TEXELS || !finite_f32(header.probe_spacing) ||
	   header.probe_spacing <= 0 {
		return {}, .Layout
	}
	if header.probe_atlas_columns == 0 || header.probe_atlas_columns > header.probe_count {
		return {}, .Layout
	}
	columns := u64(header.probe_atlas_columns)
	probe_atlas_width := columns * PROBE_TEXELS
	probe_atlas_height := (probe_count + columns - 1) / columns * PROBE_TEXELS
	if probe_atlas_width > MAX_PROBE_ATLAS_DIM || probe_atlas_height > MAX_PROBE_ATLAS_DIM {
		return {}, .Layout
	}
	if !finite_vec3(header.probe_min) {
		return {}, .Layout
	}

	atlas_section := sections[int(Section_Kind.Atlas) - 1]
	faces_section := sections[int(Section_Kind.Faces) - 1]
	slots_section := sections[int(Section_Kind.Slots) - 1]
	irradiance_section := sections[int(Section_Kind.Probe_Irradiance) - 1]
	moments_section := sections[int(Section_Kind.Probe_Moments) - 1]
	state_section := sections[int(Section_Kind.Probe_State) - 1]

	atlas_texels := u64(header.atlas_width) * u64(header.atlas_height)
	if !check_raw_section(atlas_section, atlas_texels * ATLAS_BYTES_PER_TEXEL) ||
	   !check_typed_section(faces_section, size_of(Face), header.face_count) ||
	   !check_typed_section(slots_section, size_of(Slot), header.slot_count) ||
	   !check_typed_section(state_section, size_of(Probe_State), header.probe_count) {
		return {}, .Section_Size
	}
	probe_texels := u64(header.probe_texels) * u64(header.probe_texels)
	if !check_raw_section(
		irradiance_section,
		probe_count * probe_texels * PROBE_BYTES_PER_IRRADIANCE_TEXEL,
	) || !check_raw_section(
		moments_section,
		probe_count * probe_texels * PROBE_BYTES_PER_MOMENT_TEXEL,
	) {
		return {}, .Section_Size
	}
	if stats.probe_count != header.probe_count ||
	   u64(stats.atlas_texels) != atlas_texels {
		return {}, .Layout
	}

	payload := digest.fnv()
	digest.write_bytes(&payload, bytes[int(header.header_bytes):])
	if payload.value != header.payload_hash {
		return {}, .Hash
	}

	data = {
		bytes    = bytes,
		header   = header,
		quality  = quality,
		stats    = stats,
		atlas    = bytes[int(atlas_section.offset):int(atlas_section.offset + atlas_section.size)],
		faces    = slice_section(bytes, faces_section, Face, int(header.face_count)),
		slots    = slice_section(bytes, slots_section, Slot, int(header.slot_count)),
		probe_states = slice_section(
			bytes,
			state_section,
			Probe_State,
			int(header.probe_count),
		),
		probe_irradiance = bytes[int(irradiance_section.offset):int(
			irradiance_section.offset + irradiance_section.size,
		)],
		probe_moments = bytes[int(moments_section.offset):int(
			moments_section.offset + moments_section.size,
		)],
		probe_atlas_width = u32(probe_atlas_width),
		probe_atlas_height = u32(probe_atlas_height),
	}
	if !layout_valid(data) {
		return {}, .Layout
	}
	return data, .None
}

destroy :: proc(data: ^Data, allocator: mem.Allocator) {
	if data.bytes != nil {
		delete(data.bytes, allocator)
	}
	data^ = {}
}

@(private)
read_value :: proc(bytes: []u8, offset: u64, value: ^$T) -> bool {
	size := u64(size_of(T))
	if offset > u64(len(bytes)) || size > u64(len(bytes)) - offset {
		return false
	}
	mem.copy(rawptr(value), raw_data(bytes[int(offset):]), int(size))
	return true
}

@(private)
check_raw_section :: proc(section: Section, size: u64) -> bool {
	return section.stride == 0 && section.count == 0 && section.size == size
}

@(private)
check_typed_section :: proc(section: Section, stride: int, count: u32) -> bool {
	return section.stride == u32(stride) &&
		section.count == count &&
		section.size == u64(stride) * u64(count)
}

@(private)
slice_section :: proc(bytes: []u8, section: Section, $T: typeid, count: int) -> []T {
	pointer := cast([^]T)(raw_data(bytes[int(section.offset):]))
	return pointer[:count]
}

@(private)
quality_valid :: proc(quality: Quality) -> bool {
	if quality.atlas_size == 0 || quality.atlas_size > MAX_ATLAS_DIM {
		return false
	}
	if quality.texels_per_meter == 0 || quality.texels_per_meter > 64 {
		return false
	}
	if quality.gutter_texels > 32 || quality.min_chart == 0 || quality.min_chart > 1024 {
		return false
	}
	if quality.lightmap_rays == 0 || quality.probe_rays == 0 || quality.bounces == 0 {
		return false
	}
	if quality.probe_texels != PROBE_TEXELS || !finite_f32(quality.probe_spacing) {
		return false
	}
	return quality.probe_spacing > 0
}

@(private)
layout_valid :: proc(data: Data) -> bool {
	for slot, slot_index in data.slots {
		if slot.face_count != 6 ||
		   u64(slot.first_face) + 6 > u64(len(data.faces)) {
			return false
		}
		for face_offset in 0 ..< 6 {
			face := data.faces[int(slot.first_face) + face_offset]
			if face.slot != u32(slot_index) || face.face != u8(face_offset) {
				return false
			}
			rect := face.uv_rect
			if !finite_f32(rect[0]) || !finite_f32(rect[1]) ||
			   !finite_f32(rect[2]) || !finite_f32(rect[3]) {
				return false
			}
			if rect[0] < 0 || rect[1] < 0 || rect[2] > 1 || rect[3] > 1 ||
			   rect[0] > rect[2] || rect[1] > rect[3] {
				return false
			}
		}
	}
	for state in data.probe_states {
		if state.valid > 1 {
			return false
		}
		for offset in state.offset {
			if !finite_f16(offset) {
				return false
			}
		}
	}
	return true
}

@(private)
finite_f32 :: proc(value: f32) -> bool {
	class := math.classify(value)
	return class != .NaN && class != .Inf && class != .Neg_Inf
}

@(private)
finite_f16 :: proc(value: f16) -> bool {
	class := math.classify(value)
	return class != .NaN && class != .Inf && class != .Neg_Inf
}

@(private)
finite_vec3 :: proc(value: [3]f32) -> bool {
	return finite_f32(value.x) && finite_f32(value.y) && finite_f32(value.z)
}
