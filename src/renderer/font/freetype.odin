package font

import "core:c"

Error :: c.int
Long :: c.long
ULong :: c.ulong
Short :: c.short
UShort :: c.ushort
Int :: c.int
UInt :: c.uint
Fixed :: c.long
Pos :: c.long

OK :: Error(0)

FACE_FLAG_MULTIPLE_MASTERS :: Long(1 << 8)

LOAD_NO_HINTING :: i32(1 << 1)
LOAD_NO_BITMAP :: i32(1 << 3)

RENDER_MODE_NORMAL :: c.int(0)
PIXEL_MODE_GRAY :: u8(2)

Library :: distinct rawptr

Vector :: struct {
	x, y: Pos,
}

BBox :: struct {
	x_min, y_min, x_max, y_max: Pos,
}

Generic :: struct {
	data:      rawptr,
	finalizer: rawptr,
}

Bitmap :: struct {
	rows:         UInt,
	width:        UInt,
	pitch:        Int,
	buffer:       [^]u8,
	num_grays:    UShort,
	pixel_mode:   u8,
	palette_mode: u8,
	palette:      rawptr,
}

Outline :: struct {
	n_contours: UShort,
	n_points:   UShort,
	points:     [^]Vector,
	tags:       [^]u8,
	contours:   [^]UShort,
	flags:      Int,
}

Glyph_Metrics :: struct {
	width, height:                                 Pos,
	hori_bearing_x, hori_bearing_y, hori_advance: Pos,
	vert_bearing_x, vert_bearing_y, vert_advance: Pos,
}

// Only the public prefix of FT_FaceRec_. The private tail is never read.
Face_Rec :: struct {
	num_faces:           Long,
	face_index:          Long,
	face_flags:          Long,
	style_flags:         Long,
	num_glyphs:          Long,
	family_name:         cstring,
	style_name:          cstring,
	num_fixed_sizes:     Int,
	available_sizes:     rawptr,
	num_charmaps:        Int,
	charmaps:            rawptr,
	generic:             Generic,
	bbox:                BBox,
	units_per_em:        UShort,
	ascender:            Short,
	descender:           Short,
	height:              Short,
	max_advance_width:   Short,
	max_advance_height:  Short,
	underline_position:  Short,
	underline_thickness: Short,
	glyph:               ^Glyph_Slot,
	size:                rawptr,
	charmap:             rawptr,
}

Face :: ^Face_Rec

Glyph_Slot :: struct {
	library:              Library,
	face:                 Face,
	next:                 ^Glyph_Slot,
	glyph_index:          UInt,
	generic:              Generic,
	metrics:              Glyph_Metrics,
	linear_hori_advance:  Fixed,
	linear_vert_advance:  Fixed,
	advance:              Vector,
	format:               UInt,
	bitmap:               Bitmap,
	bitmap_left:          Int,
	bitmap_top:           Int,
	outline:              Outline,
	num_subglyphs:        UInt,
	subglyphs:            rawptr,
	control_data:         rawptr,
	control_len:          c.long,
	lsb_delta:            Pos,
	rsb_delta:            Pos,
	other:                rawptr,
	internal:             rawptr,
}
