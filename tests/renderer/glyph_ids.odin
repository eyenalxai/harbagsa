#+vet explicit-allocators
package renderer_test

import "core:c"
import "core:unicode/utf8"

import "src:renderer"
import "src:renderer/font"

// The tests need a few glyph IDs. Shaping the character through HarfBuzz is the
// same path the renderer takes, so the ID cannot drift from the real layout.
glyph_for_rune :: proc(face: renderer.Text_Face, weight: f32, character: rune) -> int {
	data := renderer.text_face_data(face)
	blob := font.Blob_Create(raw_data(data), c.uint(len(data)), font.MEMORY_MODE_READONLY, nil, nil)
	if blob == nil {
		return -1
	}
	defer font.Blob_Destroy(blob)
	hb_face := font.Face_Create(blob, 0)
	if hb_face == nil {
		return -1
	}
	defer font.Face_Destroy(hb_face)
	hb_font := font.Font_Create(hb_face)
	if hb_font == nil {
		return -1
	}
	defer font.Font_Destroy(hb_font)
	upem := c.int(font.Face_Get_Upem(hb_face))
	font.Font_Set_Scale(hb_font, upem, upem)
	variation := font.Variation{tag = font.TAG_WGHT, value = weight}
	font.Font_Set_Variations(hb_font, &variation, 1)
	buffer := font.Buffer_Create()
	if buffer == nil {
		return -1
	}
	defer font.Buffer_Destroy(buffer)
	bytes, size := utf8.encode_rune(character)
	font.Buffer_Add_Utf8(buffer, &bytes[0], c.int(size), 0, -1)
	font.Buffer_Guess_Segment_Properties(buffer)
	font.Shape(hb_font, buffer, nil, 0)
	count: c.uint
	infos := font.Buffer_Get_Glyph_Infos(buffer, &count)
	if infos == nil || count == 0 {
		return -1
	}
	return int(infos[0].codepoint)
}
