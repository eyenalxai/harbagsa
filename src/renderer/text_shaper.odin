#+vet explicit-allocators
package renderer

import "core:c"
import "core:log"

import "src:renderer/font"

TEXT_RUN_MAX :: 128
TEXT_SHAPER_FONT_MAX :: 8

Text_Run :: struct {
	glyphs: [TEXT_RUN_MAX]int,
	x:      [TEXT_RUN_MAX]f32,
	count:  int,
	width:  f32,
}

Text_Shaper :: struct {
	blobs:  [TEXT_FACE_COUNT]^font.Hb_Blob,
	faces:  [TEXT_FACE_COUNT]^font.Hb_Face,
	fonts:  [TEXT_SHAPER_FONT_MAX]Shaper_Font,
	count:  int,
	buffer: ^font.Hb_Buffer,
}

@(private)
Shaper_Font :: struct {
	face:   Text_Face,
	weight: u16,
	font:   ^font.Hb_Font,
}

text_shaper_init :: proc() -> (shaper: Text_Shaper, ok: bool) {
	for face in Text_Face {
		data := text_face_data(face)
		shaper.blobs[face] = font.Blob_Create(
			raw_data(data),
			c.uint(len(data)),
			font.MEMORY_MODE_READONLY,
			nil,
			nil,
		)
		if shaper.blobs[face] == nil {
			log.errorf("text shaper: could not create the %v blob", face)
			text_shaper_destroy(&shaper)
			return {}, false
		}
		shaper.faces[face] = font.Face_Create(shaper.blobs[face], 0)
		if shaper.faces[face] == nil {
			log.errorf("text shaper: could not create the %v face", face)
			text_shaper_destroy(&shaper)
			return {}, false
		}
	}
	shaper.buffer = font.Buffer_Create()
	if shaper.buffer == nil {
		log.error("text shaper: could not create the buffer")
		text_shaper_destroy(&shaper)
		return {}, false
	}
	return shaper, true
}

text_shaper_destroy :: proc(shaper: ^Text_Shaper) {
	for shaper_font in shaper.fonts[:shaper.count] {
		font.Font_Destroy(shaper_font.font)
	}
	shaper.count = 0
	if shaper.buffer != nil {
		font.Buffer_Destroy(shaper.buffer)
		shaper.buffer = nil
	}
	for face in Text_Face {
		if shaper.faces[face] != nil {
			font.Face_Destroy(shaper.faces[face])
			shaper.faces[face] = nil
		}
		if shaper.blobs[face] != nil {
			font.Blob_Destroy(shaper.blobs[face])
			shaper.blobs[face] = nil
		}
	}
}

@(private)
text_shaper_font :: proc(shaper: ^Text_Shaper, face: Text_Face, weight: u16) -> ^font.Hb_Font {
	for shaper_font in shaper.fonts[:shaper.count] {
		if shaper_font.face == face && shaper_font.weight == weight {
			return shaper_font.font
		}
	}
	if shaper.count >= TEXT_SHAPER_FONT_MAX {
		return nil
	}
	hb_font := font.Font_Create(shaper.faces[face])
	if hb_font == nil {
		return nil
	}
	upem := c.int(font.Face_Get_Upem(shaper.faces[face]))
	font.Font_Set_Scale(hb_font, upem, upem)
	variation := font.Variation{tag = font.TAG_WGHT, value = f32(weight)}
	font.Font_Set_Variations(hb_font, &variation, 1)
	shaper.fonts[shaper.count] = {face = face, weight = weight, font = hb_font}
	shaper.count += 1
	return hb_font
}

text_style_weight :: proc(style: Text_Type) -> u16 {
	if style.face == .Mono {
		return text_mono_weight(style.weight)
	}
	return text_weight_key(style.weight)
}

text_shape :: proc(atlas: ^Text_Atlas, style: Text_Type, text: string, run: ^Text_Run) -> bool {
	run^ = {}
	if len(text) == 0 {
		return true
	}
	source := text
	if len(text) > TEXT_RUN_MAX {
		cut := TEXT_RUN_MAX
		for cut > 0 && text[cut] & 0xC0 == 0x80 {
			cut -= 1
		}
		source = text[:cut]
	}
	capped: [TEXT_RUN_MAX]u8
	if style.caps {
		for index in 0 ..< len(source) {
			character := source[index]
			if character >= 'a' && character <= 'z' {
				character -= 'a' - 'A'
			}
			capped[index] = character
		}
		source = string(capped[:len(source)])
	}

	shaper := &atlas.shaper
	hb_font := text_shaper_font(shaper, style.face, text_style_weight(style))
	if hb_font == nil {
		return false
	}

	font.Buffer_Clear_Contents(shaper.buffer)
	font.Buffer_Add_Utf8(shaper.buffer, raw_data(source), c.int(len(source)), 0, -1)
	font.Buffer_Guess_Segment_Properties(shaper.buffer)
	font.Shape(hb_font, shaper.buffer, nil, 0)

	count: c.uint
	infos := font.Buffer_Get_Glyph_Infos(shaper.buffer, &count)
	positions := font.Buffer_Get_Glyph_Positions(shaper.buffer, &count)
	if infos == nil || positions == nil {
		return true
	}

	upem := f32(font.Face_Get_Upem(shaper.faces[style.face]))
	scale := style.size / upem
	pen := f32(0)
	emitted := 0
	for index in 0 ..< int(count) {
		glyph := infos[index].codepoint
		if glyph == 0 {
			continue
		}
		if emitted >= TEXT_RUN_MAX {
			break
		}
		run.glyphs[emitted] = int(glyph)
		run.x[emitted] = pen + f32(positions[index].x_offset) * scale
		pen += f32(positions[index].x_advance) * scale
		if style.tracking != 0 {
			pen += style.tracking * style.size
		}
		emitted += 1
	}
	run.count = emitted
	run.width = pen
	if style.tracking != 0 && emitted > 0 {
		run.width -= style.tracking * style.size
	}
	return true
}
