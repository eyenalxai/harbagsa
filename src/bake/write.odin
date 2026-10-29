#+vet explicit-allocators
package bake

import "core:mem"

import "src:digest"

Artifact_Input :: struct {
	key:              u64,
	quality:          Quality,
	stats:            Stats,
	faces:            []Face,
	slots:            []Slot,
	probe_states:     []Probe_State,
	probe_min:        [3]f32,
	probe_spacing:    f32,
	probe_counts:     [3]u32,
	probe_texels:     u32,
	probe_columns:    u32,
	atlas:            []u8,
	probe_irradiance: []u8,
	probe_moments:    []u8,
}

encode_artifact :: proc(
	input: Artifact_Input,
	allocator: mem.Allocator,
) -> (
	bytes: []u8,
	payload_hash: u64,
	err: Build_Error,
) {
	atlas_texels := u64(input.quality.atlas_size) * u64(input.quality.atlas_size)
	probe_count := u64(len(input.probe_states))
	probe_texels := u64(input.probe_texels) * u64(input.probe_texels)
	if u64(len(input.atlas)) != atlas_texels * ATLAS_BYTES_PER_TEXEL ||
	   u64(len(input.probe_irradiance)) != probe_count * probe_texels * PROBE_BYTES_PER_IRRADIANCE_TEXEL ||
	   u64(len(input.probe_moments)) != probe_count * probe_texels * PROBE_BYTES_PER_MOMENT_TEXEL {
		return nil, 0, .Artifact
	}
	if len(input.faces) != len(input.slots) * FACE_COUNT {
		return nil, 0, .Artifact
	}

	offsets: [SECTION_KIND_COUNT]u64
	offset := align16(u64(size_of(Header)) + u64(SECTION_KIND_COUNT) * u64(size_of(Section)))
	offsets[int(Section_Kind.Atlas) - 1] = offset
	offset = align16(offset + u64(len(input.atlas)))
	offsets[int(Section_Kind.Faces) - 1] = offset
	offset = align16(offset + u64(len(input.faces)) * u64(size_of(Face)))
	offsets[int(Section_Kind.Slots) - 1] = offset
	offset = align16(offset + u64(len(input.slots)) * u64(size_of(Slot)))
	offsets[int(Section_Kind.Probe_Irradiance) - 1] = offset
	offset = align16(offset + u64(len(input.probe_irradiance)))
	offsets[int(Section_Kind.Probe_Moments) - 1] = offset
	offset = align16(offset + u64(len(input.probe_moments)))
	offsets[int(Section_Kind.Probe_State) - 1] = offset
	offset = align16(offset + u64(len(input.probe_states)) * u64(size_of(Probe_State)))
	offsets[int(Section_Kind.Quality) - 1] = offset
	offset = align16(offset + u64(size_of(Quality)))
	offsets[int(Section_Kind.Stats) - 1] = offset
	offset = align16(offset + u64(size_of(Stats)))

	bytes = make([]u8, int(offset), allocator)
	mem.set(raw_data(bytes), 0, len(bytes))

	header := Header {
		magic               = MAGIC,
		format_version      = FORMAT_VERSION,
		header_bytes        = u16(size_of(Header)),
		tool_version        = TOOL_VERSION,
		flags               = 0,
		bake_key            = input.key,
		payload_hash        = 0,
		atlas_width         = input.quality.atlas_size,
		atlas_height        = input.quality.atlas_size,
		atlas_format        = u32(Atlas_Format.RGBA16F),
		face_count          = u32(len(input.faces)),
		slot_count          = u32(len(input.slots)),
		probe_count         = u32(probe_count),
		probe_texels        = input.probe_texels,
		probe_atlas_columns = input.probe_columns,
		probe_min           = input.probe_min,
		probe_spacing       = input.probe_spacing,
		probe_counts        = input.probe_counts,
		section_count       = SECTION_KIND_COUNT,
		section_table_offset = u64(size_of(Header)),
	}
	write_value(bytes, 0, &header)

	sections := [SECTION_KIND_COUNT]Section {
		{
			kind = .Atlas,
			offset = offsets[int(Section_Kind.Atlas) - 1],
			size = u64(len(input.atlas)),
		},
		{
			kind = .Faces,
			offset = offsets[int(Section_Kind.Faces) - 1],
			size = u64(len(input.faces)) * u64(size_of(Face)),
			stride = u32(size_of(Face)),
			count = u32(len(input.faces)),
		},
		{
			kind = .Slots,
			offset = offsets[int(Section_Kind.Slots) - 1],
			size = u64(len(input.slots)) * u64(size_of(Slot)),
			stride = u32(size_of(Slot)),
			count = u32(len(input.slots)),
		},
		{
			kind = .Probe_Irradiance,
			offset = offsets[int(Section_Kind.Probe_Irradiance) - 1],
			size = u64(len(input.probe_irradiance)),
		},
		{
			kind = .Probe_Moments,
			offset = offsets[int(Section_Kind.Probe_Moments) - 1],
			size = u64(len(input.probe_moments)),
		},
		{
			kind = .Probe_State,
			offset = offsets[int(Section_Kind.Probe_State) - 1],
			size = u64(len(input.probe_states)) * u64(size_of(Probe_State)),
			stride = u32(size_of(Probe_State)),
			count = u32(len(input.probe_states)),
		},
		{
			kind = .Quality,
			offset = offsets[int(Section_Kind.Quality) - 1],
			size = u64(size_of(Quality)),
			stride = u32(size_of(Quality)),
			count = 1,
		},
		{
			kind = .Stats,
			offset = offsets[int(Section_Kind.Stats) - 1],
			size = u64(size_of(Stats)),
			stride = u32(size_of(Stats)),
			count = 1,
		},
	}
	for index in 0 ..< SECTION_KIND_COUNT {
		write_value(bytes, int(header.section_table_offset) + index * size_of(Section), &sections[index])
	}

	copy_slice(bytes, int(offsets[int(Section_Kind.Atlas) - 1]), input.atlas)
	copy_slice(bytes, int(offsets[int(Section_Kind.Faces) - 1]), mem.slice_to_bytes(input.faces))
	copy_slice(bytes, int(offsets[int(Section_Kind.Slots) - 1]), mem.slice_to_bytes(input.slots))
	copy_slice(
		bytes,
		int(offsets[int(Section_Kind.Probe_Irradiance) - 1]),
		input.probe_irradiance,
	)
	copy_slice(bytes, int(offsets[int(Section_Kind.Probe_Moments) - 1]), input.probe_moments)
	copy_slice(
		bytes,
		int(offsets[int(Section_Kind.Probe_State) - 1]),
		mem.slice_to_bytes(input.probe_states),
	)
	quality := input.quality
	stats := input.stats
	write_value(bytes, int(offsets[int(Section_Kind.Quality) - 1]), &quality)
	write_value(bytes, int(offsets[int(Section_Kind.Stats) - 1]), &stats)

	hash := digest.fnv()
	digest.write_bytes(&hash, bytes[int(header.header_bytes):])
	header.payload_hash = hash.value
	write_value(bytes, 0, &header)
	return bytes, hash.value, .None
}

@(private)
align16 :: proc(value: u64) -> u64 {
	return (value + 15) & ~u64(15)
}

@(private)
write_value :: proc(bytes: []u8, offset: int, value: ^$T) {
	mem.copy(raw_data(bytes[offset:]), rawptr(value), size_of(T))
}

@(private)
copy_slice :: proc(bytes: []u8, offset: int, source: []u8) {
	if len(source) == 0 {
		return
	}
	mem.copy(raw_data(bytes[offset:]), raw_data(source), len(source))
}
