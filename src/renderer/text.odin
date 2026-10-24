#+vet explicit-allocators
package renderer

import "core:math"

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

// Falls back to the nearest weight of the same face, then the nearest size. A
// style that names a layer the atlas does not have still draws in its own face.
text_layer_index :: proc(atlas: ^Text_Atlas, type: Text_Type) -> int {
	px := text_layer_px(type)
	weight := text_style_weight(type)
	best := -1
	best_distance := max(f32)
	for layer, index in atlas.layers[:atlas.count] {
		if layer.key.face != type.face {
			continue
		}
		if layer.key.weight == weight && layer.key.px == px {
			return index
		}
		distance :=
			abs(f32(layer.key.weight) - f32(weight)) * 1000.0 +
			abs(f32(layer.key.px) - f32(px))
		if distance < best_distance {
			best_distance = distance
			best = index
		}
	}
	return best
}

// Every face, weight, and pixel size a theme can draw, sorted so two builds from
// the same theme compare equal.
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
		text_layer_set_add(
			&set,
			{face = style.face, weight = text_style_weight(style), px = text_layer_px(style)},
		)
	}
	mono_weight := text_mono_weight(theme.type_body.weight)
	text_layer_set_add(
		&set,
		{face = .Mono, weight = mono_weight, px = text_layer_px(theme.type_body)},
	)
	text_layer_set_add(
		&set,
		{face = .Mono, weight = mono_weight, px = text_layer_px(theme.type_caption)},
	)
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
	index := text_layer_index(atlas, style)
	if index < 0 {
		return 0
	}
	return atlas.layers[index].ascent
}

text_descent :: proc(atlas: ^Text_Atlas, style: Text_Type) -> f32 {
	index := text_layer_index(atlas, style)
	if index < 0 {
		return 0
	}
	return atlas.layers[index].descent
}

// Distance from the top of a line box to the baseline, with the ascent and
// descent centred in the leading.
text_baseline :: proc(atlas: ^Text_Atlas, style: Text_Type) -> f32 {
	ascent := text_ascent(atlas, style)
	descent := text_descent(atlas, style)
	return (style.line_height - (ascent - descent)) * 0.5 + ascent
}

text_measure :: proc(atlas: ^Text_Atlas, style: Text_Type, text: string) -> f32 {
	if text_layer_index(atlas, style) < 0 {
		return 0
	}
	run: Text_Run
	if !text_shape(atlas, style, text, &run) {
		return 0
	}
	return run.width
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
	layer_index := text_layer_index(&o.atlas, style.type)
	if layer_index < 0 {
		return
	}
	layer := &o.atlas.layers[layer_index]
	run: Text_Run
	if !text_shape(&o.atlas, style.type, text, &run) {
		return
	}
	// A coverage atlas is only exact on the pixel grid, so the line snaps
	// vertically and each glyph snaps horizontally. Its sub-pixel offset moves
	// into the phase, which keeps the advance fractional.
	row := math.round(baseline)
	for index in 0 ..< run.count {
		glyph_index := run.glyphs[index]
		if glyph_index < 0 || glyph_index >= len(layer.glyphs) {
			continue
		}
		glyph := layer.glyphs[glyph_index]
		if !glyph.present {
			continue
		}
		origin, phase := text_place(x + run.x[index])
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
