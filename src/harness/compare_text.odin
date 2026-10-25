#+vet explicit-allocators
package harness

import "core:mem"
import "core:strings"

import "src:renderer"

Compare_Text :: struct {
	atlas: renderer.Text_Atlas,
	style: renderer.Text_Type,
	ok:    bool,
}

compare_text_init :: proc(allocator: mem.Allocator, size: f32 = 15) -> Compare_Text {
	text: Compare_Text
	set: renderer.Text_Layer_Set
	renderer.text_layer_set_add(
		&set,
		{face = .Sans, weight = 500, px = u32(size)},
	)
	atlas, built := renderer.text_atlas_build(allocator, &set)
	if !built {
		return text
	}
	text.atlas = atlas
	text.style = {
		size        = size,
		line_height = size * 1.4,
		face        = .Sans,
		weight      = 500,
	}
	text.ok = true
	return text
}

compare_text_destroy :: proc(text: ^Compare_Text) {
	renderer.text_atlas_destroy(&text.atlas)
	text^ = {}
}

compare_text_width :: proc(text: ^Compare_Text, value: string) -> int {
	if !text.ok {
		return 0
	}
	return int(renderer.text_measure(&text.atlas, text.style, value) + 0.5)
}

compare_text_fit :: proc(text: ^Compare_Text, value: string, max_width: int) -> string {
	if compare_text_width(text, value) <= max_width {
		return value
	}
	ellipsis := "..."
	width := max_width - compare_text_width(text, ellipsis)
	if width <= 0 {
		return ellipsis
	}
	cut := len(value)
	for cut > 0 {
		candidate := value[:cut]
		if compare_text_width(text, candidate) <= width {
			return strings.concatenate({candidate, ellipsis}, context.temp_allocator)
		}
		cut -= 1
	}
	return ellipsis
}

compare_text_draw :: proc(
	canvas: ^Compare_Canvas,
	text: ^Compare_Text,
	value: string,
	x, baseline: int,
	color: [4]u8,
) -> int {
	if !text.ok || value == "" {
		return 0
	}
	layer_index := renderer.text_layer_index(&text.atlas, text.style)
	if layer_index < 0 {
		return 0
	}
	layer := &text.atlas.layers[layer_index]
	run: renderer.Text_Run
	if !renderer.text_shape(&text.atlas, text.style, value, &run) {
		return 0
	}
	for index in 0 ..< run.count {
		glyph_index := run.glyphs[index]
		if glyph_index < 0 || glyph_index >= len(layer.glyphs) {
			continue
		}
		glyph := layer.glyphs[glyph_index]
		if !glyph.present {
			continue
		}
		origin, phase := renderer.text_place(f32(x) + run.x[index])
		placed := glyph.phases[phase]
		left := int(origin + placed.offset.x + 0.5)
		top := int(f32(baseline) + placed.offset.y + 0.5)
		cell_x := int(placed.uv.x * f32(text.atlas.width) + 0.5)
		cell_y := int(placed.uv.y * f32(text.atlas.height) + 0.5)
		cell_w := int(placed.size.x + 0.5)
		cell_h := int(placed.size.y + 0.5)
		if cell_x < 0 || cell_y < 0 || cell_x + cell_w > int(text.atlas.width) {
			continue
		}
		if cell_y + cell_h > int(text.atlas.height) {
			continue
		}
		for row in 0 ..< cell_h {
			for column in 0 ..< cell_w {
				coverage := text.atlas.pixels[(cell_y + row) * int(text.atlas.width) + cell_x + column]
				if coverage == 0 {
					continue
				}
				compare_canvas_blend_pixel(
					canvas,
					left + column,
					top + row,
					color,
					coverage,
				)
			}
		}
	}
	return int(run.width + 0.5)
}
