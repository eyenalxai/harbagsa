package font

import "core:c"

HARFBUZZ_LIB :: "../../../vendor/harfbuzz/lib/linux-amd64/libharfbuzz.a"

when !#exists(HARFBUZZ_LIB) {
	#panic("HarfBuzz archive is missing; run `make` to build it")
}

@(export, extra_linker_flags="-lstdc++ -lm")
foreign import hb {HARFBUZZ_LIB}

Hb_Blob :: struct {}
Hb_Face :: struct {}
Hb_Font :: struct {}
Hb_Buffer :: struct {}

TAG_WGHT :: u32(0x77676874)
MEMORY_MODE_READONLY :: c.int(1)

Glyph_Info :: struct {
	codepoint: u32,
	mask:      u32,
	cluster:   u32,
	var1:      u32,
	var2:      u32,
}

Glyph_Position :: struct {
	x_advance: i32,
	y_advance: i32,
	x_offset:  i32,
	y_offset:  i32,
	var:       u32,
}

Variation :: struct {
	tag:   u32,
	value: f32,
}

Destroy_Func :: #type proc "c" (user_data: rawptr)

@(default_calling_convention="c")
foreign hb {
	@(link_name="hb_blob_create")
	Blob_Create :: proc(
		data: [^]u8,
		length: c.uint,
		mode: c.int,
		user_data: rawptr,
		destroy: Destroy_Func,
	) -> ^Hb_Blob ---

	@(link_name="hb_blob_destroy")
	Blob_Destroy :: proc(blob: ^Hb_Blob) ---

	@(link_name="hb_face_create")
	Face_Create :: proc(blob: ^Hb_Blob, index: c.uint) -> ^Hb_Face ---

	@(link_name="hb_face_get_upem")
	Face_Get_Upem :: proc(face: ^Hb_Face) -> c.uint ---

	@(link_name="hb_face_destroy")
	Face_Destroy :: proc(face: ^Hb_Face) ---

	@(link_name="hb_font_create")
	Font_Create :: proc(face: ^Hb_Face) -> ^Hb_Font ---

	@(link_name="hb_font_destroy")
	Font_Destroy :: proc(font: ^Hb_Font) ---

	@(link_name="hb_font_set_scale")
	Font_Set_Scale :: proc(font: ^Hb_Font, x_scale, y_scale: c.int) ---

	@(link_name="hb_font_set_variations")
	Font_Set_Variations :: proc(font: ^Hb_Font, variations: ^Variation, length: c.uint) ---

	@(link_name="hb_buffer_create")
	Buffer_Create :: proc() -> ^Hb_Buffer ---

	@(link_name="hb_buffer_destroy")
	Buffer_Destroy :: proc(buffer: ^Hb_Buffer) ---

	@(link_name="hb_buffer_clear_contents")
	Buffer_Clear_Contents :: proc(buffer: ^Hb_Buffer) ---

	@(link_name="hb_buffer_add_utf8")
	Buffer_Add_Utf8 :: proc(
		buffer: ^Hb_Buffer,
		text: [^]u8,
		text_length: c.int,
		item_offset: c.uint,
		item_length: c.int,
	) ---

	@(link_name="hb_buffer_guess_segment_properties")
	Buffer_Guess_Segment_Properties :: proc(buffer: ^Hb_Buffer) ---

	@(link_name="hb_shape")
	Shape :: proc(font: ^Hb_Font, buffer: ^Hb_Buffer, features: rawptr, num_features: c.uint) ---

	@(link_name="hb_buffer_get_glyph_infos")
	Buffer_Get_Glyph_Infos :: proc(buffer: ^Hb_Buffer, length: ^c.uint) -> [^]Glyph_Info ---

	@(link_name="hb_buffer_get_glyph_positions")
	Buffer_Get_Glyph_Positions :: proc(buffer: ^Hb_Buffer, length: ^c.uint) -> [^]Glyph_Position ---
}
