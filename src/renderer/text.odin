#+vet explicit-allocators
package renderer

import "core:unicode/utf8"

// Rects carry this uv so the fragment shader skips the atlas sample. A negative
// coordinate cannot collide with a real glyph, whose uv is always in [0, 1].
TEXT_UV_NONE :: [2]f32{-1, -1}

Text_Style :: struct {
	type:  Text_Type,
	color: [4]f32,
}

Text_Align :: enum {
	Left,
	Center,
	Right,
}

text_scale :: proc(atlas: ^Text_Atlas, style: Text_Type) -> f32 {
	return style.size / atlas.base_px
}

text_ascent :: proc(atlas: ^Text_Atlas, style: Text_Type) -> f32 {
	return atlas.ascent * text_scale(atlas, style)
}

text_descent :: proc(atlas: ^Text_Atlas, style: Text_Type) -> f32 {
	return atlas.descent * text_scale(atlas, style)
}

// Distance from the top of a line box to the baseline, with the ascent and
// descent centred in the leading.
text_baseline :: proc(atlas: ^Text_Atlas, style: Text_Type) -> f32 {
	ascent := text_ascent(atlas, style)
	descent := text_descent(atlas, style)
	return (style.line_height - (ascent - descent)) * 0.5 + ascent
}

Text_Cursor :: struct {
	atlas: ^Text_Atlas,
	style: Text_Type,
	text:  string,
	scale: f32,
	byte:    int,
	pen:     f32,
	prev:    int,
	emitted: int,
}

text_cursor_init :: proc(cursor: ^Text_Cursor, atlas: ^Text_Atlas, style: Text_Type, text: string) {
	cursor.atlas = atlas
	cursor.style = style
	cursor.text = text
	cursor.scale = text_scale(atlas, style)
	cursor.byte = 0
	cursor.pen = 0
	cursor.prev = -1
	cursor.emitted = 0
}

// Yields one placeable glyph at a time so measuring and drawing cannot drift
// apart: both walk exactly this loop.
text_cursor_next :: proc(cursor: ^Text_Cursor) -> (glyph: Text_Glyph, x: f32, ok: bool) {
	for cursor.byte < len(cursor.text) {
		r, width := utf8.decode_rune_in_string(cursor.text[cursor.byte:])
		cursor.byte += width

		index, found := text_codepoint_index(r)
		if !found {
			continue
		}
		if cursor.prev >= 0 {
			cursor.pen +=
				cursor.atlas.kern[int(cursor.style.weight)][cursor.prev * TEXT_CODEPOINT_COUNT + index] *
				cursor.scale
		}

		glyph = cursor.atlas.glyphs[int(cursor.style.weight)][index]
		x = cursor.pen
		cursor.pen += glyph.advance * cursor.scale
		if cursor.style.tracking != 0 {
			cursor.pen += cursor.style.tracking * cursor.style.size
		}
		cursor.prev = index
		cursor.emitted += 1
		return glyph, x, true
	}
	return {}, 0, false
}

text_measure :: proc(atlas: ^Text_Atlas, style: Text_Type, text: string) -> f32 {
	cursor: Text_Cursor
	text_cursor_init(&cursor, atlas, style, text)
	for {
		_, _, ok := text_cursor_next(&cursor)
		if !ok {
			break
		}
	}
	// Tracking is a gap between glyphs; the last one must not carry a trailing
	// gap or every centred string sits half a tracking unit off centre.
	if cursor.style.tracking != 0 && cursor.emitted > 0 {
		cursor.pen -= cursor.style.tracking * cursor.style.size
	}
	return cursor.pen
}

text_emit :: proc(o: ^Overlay, x, baseline: f32, style: Text_Style, text: string) {
	cursor: Text_Cursor
	text_cursor_init(&cursor, &o.atlas, style.type, text)
	for {
		glyph, pen_x, ok := text_cursor_next(&cursor)
		if !ok {
			break
		}
		if !glyph.present {
			continue
		}
		width := (glyph.uv.z - glyph.uv.x) * f32(o.atlas.width)
		height := (glyph.uv.w - glyph.uv.y) * f32(o.atlas.height)
		left := x + pen_x + glyph.offset.x * cursor.scale
		top := baseline + glyph.offset.y * cursor.scale
		right := left + width * cursor.scale
		bottom := top + height * cursor.scale
		hud_emit_textured_quad(
			o,
			{left, top},
			{right, top},
			{right, bottom},
			{left, bottom},
			{glyph.uv.x, glyph.uv.y},
			{glyph.uv.z, glyph.uv.w},
			style.color,
		)
	}
}

text_emit_aligned :: proc(
	o: ^Overlay,
	anchor_x, baseline: f32,
	style: Text_Style,
	text: string,
	align: Text_Align,
) {
	x := anchor_x
	switch align {
	case .Left:
	case .Center:
		x -= text_measure(&o.atlas, style.type, text) * 0.5
	case .Right:
		x -= text_measure(&o.atlas, style.type, text)
	}
	text_emit(o, x, baseline, style, text)
}
