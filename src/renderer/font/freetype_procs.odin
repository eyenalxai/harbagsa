package font

import "core:c"

FREETYPE_LIB :: "../../../vendor/freetype/lib/linux-amd64/libfreetype.a"

when !#exists(FREETYPE_LIB) {
	#panic("FreeType archive is missing; run `make` to build it")
}

@(export)
foreign import ft {FREETYPE_LIB}

@(default_calling_convention="c", link_prefix="FT_")
foreign ft {
	Init_FreeType              :: proc(alibrary: ^Library) -> Error ---
	Done_FreeType              :: proc(library: Library) -> Error ---
	New_Memory_Face            :: proc(library: Library, file_base: [^]u8, file_size: Long, face_index: Long, aface: ^Face) -> Error ---
	Done_Face                  :: proc(face: Face) -> Error ---
	Set_Pixel_Sizes            :: proc(face: Face, pixel_width, pixel_height: UInt) -> Error ---
	Set_Var_Design_Coordinates :: proc(face: Face, num_coords: UInt, coords: ^Fixed) -> Error ---
	Load_Glyph                 :: proc(face: Face, glyph_index: UInt, load_flags: i32) -> Error ---
	Render_Glyph               :: proc(slot: ^Glyph_Slot, render_mode: c.int) -> Error ---
	Outline_Translate          :: proc(outline: ^Outline, x_offset, y_offset: Pos) ---
}
