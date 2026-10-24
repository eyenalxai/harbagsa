#+vet explicit-allocators
package renderer

import "core:math"
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

text_layer_px :: proc(type: Text_Type) -> u32 {
	return u32(max(math.round(type.size), 1))
}

// Falls back to the nearest pixel size of the same face. A style that names a
// size the atlas was not built for still draws, at the closest size it has.
text_layer_index :: proc(atlas: ^Text_Atlas, type: Text_Type) -> int {
	px := text_layer_px(type)
	best := 0
	best_distance := max(f32)
	for layer, index in atlas.layers[:atlas.count] {
		if layer.key.weight == type.weight {
			if layer.key.px == px {
				return index
			}
			distance := abs(f32(layer.key.px) - f32(px))
			if distance < best_distance {
				best_distance = distance
				best = index
			}
		}
	}
	return best
}

// Every face and pixel size a theme can draw, sorted so two builds from the same
// theme compare equal.
text_theme_layer_set :: proc(theme: UI_Theme) -> Text_Layer_Set {
	set: Text_Layer_Set
	styles := [5]Text_Type {
		theme.type_title,
		theme.type_body,
		theme.type_body_strong,
		theme.type_caption,
		theme.type_caption_caps,
	}
	for style in styles {
		text_layer_set_add(&set, {weight = style.weight, px = text_layer_px(style)})
	}
	text_layer_set_add(&set, {weight = .Mono, px = text_layer_px(theme.type_body)})
	return set
}

text_atlas_covers :: proc(atlas: ^Text_Atlas, set: Text_Layer_Set) -> bool {
	if atlas.pixels == nil || atlas.count != set.count {
		return false
	}
	for layer, index in atlas.layers[:atlas.count] {
		if layer.key != set.keys[index] {
			return false
		}
	}
	return true
}

text_ascent :: proc(atlas: ^Text_Atlas, style: Text_Type) -> f32 {
	return atlas.layers[text_layer_index(atlas, style)].ascent
}

text_descent :: proc(atlas: ^Text_Atlas, style: Text_Type) -> f32 {
	return atlas.layers[text_layer_index(atlas, style)].descent
}

// Distance from the top of a line box to the baseline, with the ascent and
// descent centred in the leading.
text_baseline :: proc(atlas: ^Text_Atlas, style: Text_Type) -> f32 {
	ascent := text_ascent(atlas, style)
	descent := text_descent(atlas, style)
	return (style.line_height - (ascent - descent)) * 0.5 + ascent
}

Text_Cursor :: struct {
	atlas:   ^Text_Atlas,
	layer:   int,
	style:   Text_Type,
	text:    string,
	byte:    int,
	pen:     f32,
	prev:    int,
	emitted: int,
}

text_cursor_init :: proc(cursor: ^Text_Cursor, atlas: ^Text_Atlas, style: Text_Type, text: string) {
	cursor.atlas = atlas
	cursor.layer = text_layer_index(atlas, style)
	cursor.style = style
	cursor.text = text
	cursor.byte = 0
	cursor.pen = 0
	cursor.prev = -1
	cursor.emitted = 0
}

// Yields one placeable glyph at a time so measuring and drawing cannot drift
// apart: both walk exactly this loop.
text_cursor_next :: proc(cursor: ^Text_Cursor) -> (glyph: Text_Glyph, x: f32, ok: bool) {
	layer := &cursor.atlas.layers[cursor.layer]
	for cursor.byte < len(cursor.text) {
		r, width := utf8.decode_rune_in_string(cursor.text[cursor.byte:])
		cursor.byte += width
		if cursor.style.caps && r >= 'a' && r <= 'z' {
			r -= 'a' - 'A'
		}

		index, found := text_codepoint_index(r)
		if !found {
			continue
		}
		if cursor.prev >= 0 {
			cursor.pen += layer.kern[cursor.prev * TEXT_CODEPOINT_COUNT + index]
		}

		glyph = layer.glyphs[index]
		x = cursor.pen
		cursor.pen += glyph.advance
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

// Splits a pen position into a whole-pixel origin and a sub-pixel phase. The
// quantized position is within 1/8 px of the true one, and the origin is always
// an integer so the coverage atlas samples one texel per pixel.
text_place :: proc(position: f32) -> (origin: f32, phase: int) {
	quarter := int(math.round(position * f32(TEXT_SUBPIXEL_PHASES)))
	index := int(math.floor(f32(quarter) / f32(TEXT_SUBPIXEL_PHASES)))
	return f32(index), quarter - index * TEXT_SUBPIXEL_PHASES
}

text_emit :: proc(o: ^Overlay, x, baseline: f32, style: Text_Style, text: string) {
	cursor: Text_Cursor
	text_cursor_init(&cursor, &o.atlas, style.type, text)
	// A coverage atlas is only exact on the pixel grid, so the line snaps
	// vertically and each glyph snaps horizontally. Its sub-pixel offset moves
	// into the phase, which keeps the advance fractional.
	row := math.round(baseline)
	for {
		glyph, pen_x, ok := text_cursor_next(&cursor)
		if !ok {
			break
		}
		if !glyph.present {
			continue
		}
		origin, phase := text_place(x + pen_x)
		placed := glyph.phases[phase]
		left := origin + placed.offset.x
		top := row + placed.offset.y
		right := left + placed.size.x
		bottom := top + placed.size.y
		hud_emit_textured_quad(
			o,
			{left, top},
			{right, top},
			{right, bottom},
			{left, bottom},
			{placed.uv.x, placed.uv.y},
			{placed.uv.z, placed.uv.w},
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
