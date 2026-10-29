#+vet explicit-allocators
#+vet !unused-procedures // the renderer loads the artifact and reports the error
package bake

Atlas_Format :: enum u32 {
	RGBA16F = 1,
}

Section_Kind :: enum u32 {
	Atlas = 1,
	Faces,
	Slots,
	Probe_Irradiance,
	Probe_Moments,
	Probe_State,
	Quality,
	Stats,
}

SECTION_KIND_COUNT :: 8
MAX_ATLAS_DIM :: 8192
MAX_PROBE_COUNT :: 1 << 22

// The offsets are explicit and every payload section starts on a 16-byte
// boundary. `Header` and `Section` are packed so a future writer can emit the
// struct with no padding surprises.
Header :: struct #packed {
	magic:                [4]u8,
	format_version:       u16,
	header_bytes:         u16,
	tool_version:         u32,
	flags:                u32,
	bake_key:             u64,
	payload_hash:         u64,
	atlas_width:          u32,
	atlas_height:         u32,
	atlas_format:         u32,
	face_count:           u32,
	slot_count:           u32,
	probe_count:          u32,
	probe_texels:         u32,
	probe_atlas_columns:  u32,
	probe_min:            [3]f32,
	probe_spacing:        f32,
	probe_counts:         [3]u32,
	section_count:        u32,
	section_table_offset: u64,
}

Section :: struct #packed {
	kind:   Section_Kind,
	offset: u64,
	size:   u64,
	stride: u32,
	count:  u32,
}

Face :: struct #packed {
	key:     u64,
	slot:    u32,
	face:    u8,
	_pad:    [3]u8,
	uv_rect: [4]f32,
}

Slot :: struct #packed {
	key:        u64,
	first_face: u32,
	face_count: u32,
}

// The high half is the source and the low half is the arena index or the placed
// object id, so the two independent id spaces cannot collide.
slot_key :: proc(source: Box_Source, id: u32) -> u64 {
	return u64(source) << 32 | u64(id)
}

Probe_State :: struct #packed {
	// One means the probe has a usable capture point. `offset` moves that point
	// out of static geometry, or to the source of a dilated value; the runtime
	// samples and tests depth at grid position + offset.
	valid:   u8,
	_pad:    u8,
	offset:  [3]f16,
}

Stats :: struct #packed {
	// Wall time is telemetry, not bake identity: the writer stores zero so the
	// same static input and quality produce byte-identical artifacts. The tool
	// prints its measured time.
	bake_ms:       u32,
	_pad:          u32,
	lightmap_rays: u64,
	probe_rays:    u64,
	atlas_texels:  u32,
	probe_count:   u32,
	invalid_texels: u32,
	invalid_probes: u32,
}

#assert(size_of(Header) == 104)
#assert(size_of(Section) == 28)
#assert(size_of(Face) == 32)
#assert(size_of(Slot) == 16)
#assert(size_of(Probe_State) == 8)
#assert(size_of(Stats) == 40)
#assert(size_of(Quality) == 36)

Error :: enum {
	None,
	Header,
	Magic,
	Version,
	Section_Table,
	Section_Bounds,
	Section_Size,
	Atlas_Format,
	Quality,
	Layout,
	Hash,
}

error_name :: proc(err: Error) -> string {
	switch err {
	case .None:
		return "none"
	case .Header:
		return "bad header"
	case .Magic:
		return "bad magic"
	case .Version:
		return "unsupported format version"
	case .Section_Table:
		return "bad section table"
	case .Section_Bounds:
		return "section outside the file"
	case .Section_Size:
		return "section size does not match the header"
	case .Atlas_Format:
		return "unsupported atlas format"
	case .Quality:
		return "bad quality block"
	case .Layout:
		return "bad lightmap or probe layout"
	case .Hash:
		return "payload hash mismatch"
	}
	return "unknown bake error"
}

Data :: struct {
	bytes:             []u8,
	header:            Header,
	quality:           Quality,
	stats:             Stats,
	faces:             []Face,
	slots:             []Slot,
	probe_states:      []Probe_State,
	atlas:             []u8,
	probe_irradiance:  []u8,
	probe_moments:     []u8,
	probe_atlas_width:  u32,
	probe_atlas_height: u32,
}
