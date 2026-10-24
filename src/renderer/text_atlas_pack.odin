#+vet explicit-allocators
package renderer

import "core:c"
import "core:log"
import "core:mem"

import stbrp "vendor:stb/rect_pack"
import stbtt "vendor:stb/truetype"

@(private)
Text_Glyph_Slot :: struct {
	layer: int,
	index: int,
	phase: int,
	box:   [4]c.int,
}

text_atlas_build :: proc(allocator: mem.Allocator, set: ^Text_Layer_Set) -> (atlas: Text_Atlas, ok: bool) {
	if set.count == 0 {
		log.error("text atlas: a build needs at least one layer")
		return {}, false
	}

	infos: [TEXT_LAYER_MAX]stbtt.fontinfo
	scales: [TEXT_LAYER_MAX]f32
	for key, layer in set.keys[:set.count] {
		if !stbtt.InitFont(&infos[layer], raw_data(text_face(key.weight)), 0) {
			log.errorf("text atlas: could not parse the %v face", key.weight)
			return {}, false
		}
		scales[layer] = stbtt.ScaleForMappingEmToPixels(&infos[layer], f32(key.px))
	}

	slots := make([dynamic]Text_Glyph_Slot, 0, set.count * TEXT_CODEPOINT_COUNT * TEXT_SUBPIXEL_PHASES, context.temp_allocator)
	defer delete(slots)
	area := 0
	for _, layer in set.keys[:set.count] {
		for index in 0 ..< TEXT_CODEPOINT_COUNT {
			codepoint := text_codepoint_at(index)
			for phase in 0 ..< TEXT_SUBPIXEL_PHASES {
				box := text_glyph_box(&infos[layer], scales[layer], codepoint, phase)
				if box.z <= box.x || box.w <= box.y {
					continue
				}
				append(
					&slots,
					Text_Glyph_Slot {
						layer = layer,
						index = index,
						phase = phase,
						box = box,
					},
				)
				cell := text_glyph_cell_size(box)
				area += cell.x * cell.y
			}
		}
	}

	rects := make([]stbrp.Rect, len(slots), context.temp_allocator)
	defer delete(rects, context.temp_allocator)
	for slot, index in slots {
		cell := text_glyph_cell_size(slot.box)
		rects[index] = stbrp.Rect {
			id = c.int(index),
			w  = stbrp.Coord(cell.x),
			h  = stbrp.Coord(cell.y),
		}
	}

	side := text_atlas_side_for(int(f32(area) * TEXT_ATLAS_PACK_HEADROOM))
	for {
		if side > TEXT_ATLAS_MAX_SIDE {
			log.errorf("text atlas: %d glyph phases do not fit in %dx%d", len(rects), TEXT_ATLAS_MAX_SIDE, TEXT_ATLAS_MAX_SIDE)
			return {}, false
		}
		if text_atlas_pack(rects, side) {
			break
		}
		side += TEXT_ATLAS_SIDE_STEP
	}

	atlas.width = side
	atlas.height = side
	atlas.count = set.count
	atlas.pixels = make([]u8, int(side) * int(side), allocator)
	for key, layer in set.keys[:set.count] {
		atlas.layers[layer].key = key
		text_layer_metrics(&atlas.layers[layer], &infos[layer], scales[layer])
	}

	for slot, index in slots {
		text_atlas_blit(&atlas, &infos[slot.layer], scales[slot.layer], slot, rects[index])
	}
	for layer in 0 ..< set.count {
		atlas.layers[layer].kern = text_layer_kerning(allocator, &infos[layer], scales[layer])
	}

	log.infof(
		"text atlas: %dx%d, %d layers, %d glyph phases",
		atlas.width,
		atlas.height,
		atlas.count,
		len(slots),
	)
	return atlas, true
}

@(private)
text_glyph_box :: proc(info: ^stbtt.fontinfo, scale: f32, codepoint: rune, phase: int) -> [4]c.int {
	x0, y0, x1, y1: c.int
	shift := f32(phase) / f32(TEXT_SUBPIXEL_PHASES)
	stbtt.GetCodepointBitmapBoxSubpixel(info, codepoint, scale, scale, shift, 0, &x0, &y0, &x1, &y1)
	return {x0, y0, x1, y1}
}

@(private)
text_glyph_cell_size :: proc(box: [4]c.int) -> [2]int {
	return {
		int(box.z - box.x) + TEXT_GLYPH_PADDING * 2,
		int(box.w - box.y) + TEXT_GLYPH_PADDING * 2,
	}
}

@(private)
text_atlas_side_for :: proc(area: int) -> u32 {
	side := u32(TEXT_ATLAS_MIN_SIDE)
	for int(side) * int(side) < area && side < TEXT_ATLAS_MAX_SIDE {
		side += TEXT_ATLAS_SIDE_STEP
	}
	return side
}

@(private)
text_atlas_pack :: proc(rects: []stbrp.Rect, side: u32) -> bool {
	for &rect in rects {
		rect.x = 0
		rect.y = 0
		rect.was_packed = false
	}
	nodes := make([]stbrp.Node, side, context.temp_allocator)
	defer delete(nodes, context.temp_allocator)
	context_pack: stbrp.Context
	stbrp.init_target(&context_pack, c.int(side), c.int(side), raw_data(nodes), c.int(len(nodes)))
	if stbrp.pack_rects(&context_pack, raw_data(rects), c.int(len(rects))) != 1 {
		return false
	}
	for rect in rects {
		if !rect.was_packed {
			return false
		}
	}
	return true
}

@(private)
text_layer_metrics :: proc(layer: ^Text_Layer, info: ^stbtt.fontinfo, scale: f32) {
	ascent, descent, line_gap: c.int
	stbtt.GetFontVMetrics(info, &ascent, &descent, &line_gap)
	layer.ascent = f32(ascent) * scale
	layer.descent = f32(descent) * scale
	layer.line_gap = f32(line_gap) * scale
	for index in 0 ..< TEXT_CODEPOINT_COUNT {
		advance, bearing: c.int
		stbtt.GetCodepointHMetrics(info, text_codepoint_at(index), &advance, &bearing)
		layer.glyphs[index].advance = f32(advance) * scale
	}
}

@(private)
text_atlas_blit :: proc(
	atlas: ^Text_Atlas,
	info: ^stbtt.fontinfo,
	scale: f32,
	slot: Text_Glyph_Slot,
	rect: stbrp.Rect,
) {
	cell := text_glyph_cell_size(slot.box)
	x := int(rect.x) + TEXT_GLYPH_PADDING
	y := int(rect.y) + TEXT_GLYPH_PADDING
	glyph := &atlas.layers[slot.layer].glyphs[slot.index]
	width := f32(atlas.width)
	height := f32(atlas.height)
	glyph.phases[slot.phase] = {
		uv = {
			f32(rect.x) / width,
			f32(rect.y) / height,
			f32(int(rect.x) + cell.x) / width,
			f32(int(rect.y) + cell.y) / height,
		},
		offset = {
			f32(slot.box.x - TEXT_GLYPH_PADDING),
			f32(slot.box.y - TEXT_GLYPH_PADDING),
		},
		size = {f32(cell.x), f32(cell.y)},
	}
	glyph.present = true

	shift := f32(slot.phase) / f32(TEXT_SUBPIXEL_PHASES)
	target := &atlas.pixels[y * int(atlas.width) + x]
	stbtt.MakeCodepointBitmapSubpixel(
		info,
		target,
		c.int(cell.x - TEXT_GLYPH_PADDING * 2),
		c.int(cell.y - TEXT_GLYPH_PADDING * 2),
		c.int(atlas.width),
		scale,
		scale,
		shift,
		0,
		text_codepoint_at(slot.index),
	)
}

@(private)
text_layer_kerning :: proc(allocator: mem.Allocator, info: ^stbtt.fontinfo, scale: f32) -> []f32 {
	kern := make([]f32, TEXT_CODEPOINT_COUNT * TEXT_CODEPOINT_COUNT, allocator)
	for first in 0 ..< TEXT_CODEPOINT_COUNT {
		for second in 0 ..< TEXT_CODEPOINT_COUNT {
			advance := stbtt.GetCodepointKernAdvance(
				info,
				text_codepoint_at(first),
				text_codepoint_at(second),
			)
			kern[first * TEXT_CODEPOINT_COUNT + second] = f32(advance) * scale
		}
	}
	return kern
}
