#+vet explicit-allocators
package renderer

import "core:c"
import "core:log"
import "core:mem"

import "src:renderer/font"
import stbrp "vendor:stb/rect_pack"

@(private)
Text_Glyph_Slot :: struct {
	layer:  int,
	index:  int,
	phase:  int,
	width:  int,
	height: int,
}

text_atlas_build :: proc(
	allocator: mem.Allocator,
	set: ^Text_Layer_Set,
	with_shaper := true,
) -> (atlas: Text_Atlas, ok: bool) {
	if set.count == 0 {
		log.error("text atlas: a build needs at least one layer")
		return {}, false
	}
	atlas.allocator = allocator

	library: font.Library
	if font.Init_FreeType(&library) != font.OK {
		log.error("text atlas: FreeType did not initialise")
		return {}, false
	}
	faces: [TEXT_FACE_COUNT]font.Face
	opened := 0
	defer {
		for face in Text_Face {
			if faces[face] != nil {
				_ = font.Done_Face(faces[face])
			}
		}
		_ = font.Done_FreeType(library)
	}
	for face in Text_Face {
		bytes := text_face_data(face)
		if font.New_Memory_Face(library, raw_data(bytes), font.Long(len(bytes)), 0, &faces[face]) != font.OK {
			log.errorf("text atlas: could not open the %v face", face)
			return {}, false
		}
		opened += 1
	}
	if opened != TEXT_FACE_COUNT {
		return {}, false
	}

	atlas.count = set.count
	slots := make([dynamic]Text_Glyph_Slot, 0, set.count * 256, context.temp_allocator)
	area := 0
	for key, layer_index in set.keys[:set.count] {
		face := faces[key.face]
		if !text_face_setup(face, key.weight, key.px) {
			text_atlas_destroy(&atlas)
			return {}, false
		}
		atlas.layers[layer_index].key = key
		text_layer_metrics(&atlas.layers[layer_index], face, key.px)

		glyph_count := int(face.num_glyphs)
		atlas.layers[layer_index].glyphs = make([]Text_Glyph, glyph_count, allocator)
		for index in 0 ..< glyph_count {
			for phase in 0 ..< TEXT_SUBPIXEL_PHASES {
				bitmap, _, _, rendered := text_glyph_render(face, u32(index), phase)
				if !rendered {
					continue
				}
				append(
					&slots,
					Text_Glyph_Slot {
						layer = layer_index,
						index = index,
						phase = phase,
						width = int(bitmap.width),
						height = int(bitmap.rows),
					},
				)
				area += (int(bitmap.width) + TEXT_GLYPH_PADDING * 2) * (int(bitmap.rows) + TEXT_GLYPH_PADDING * 2)
			}
		}
	}

	rects := make([]stbrp.Rect, len(slots), context.temp_allocator)
	defer delete(rects, context.temp_allocator)
	for slot, index in slots {
		cell := text_glyph_cell(slot)
		rects[index] = stbrp.Rect{id = c.int(index), w = stbrp.Coord(cell.x), h = stbrp.Coord(cell.y)}
	}

	side := text_atlas_side_for(int(f32(area) * TEXT_ATLAS_PACK_HEADROOM))
	for {
		if side > TEXT_ATLAS_MAX_SIDE {
			log.errorf("text atlas: %d glyph phases do not fit in %dx%d", len(rects), TEXT_ATLAS_MAX_SIDE, TEXT_ATLAS_MAX_SIDE)
			text_atlas_destroy(&atlas)
			return {}, false
		}
		if text_atlas_pack(rects, side) {
			break
		}
		side += TEXT_ATLAS_SIDE_STEP
	}

	atlas.width = side
	atlas.height = side
	atlas.pixels = make([]u8, int(side) * int(side), allocator)

	for key, layer_index in set.keys[:set.count] {
		face := faces[key.face]
		if !text_face_setup(face, key.weight, key.px) {
			text_atlas_destroy(&atlas)
			return {}, false
		}
		for slot, index in slots {
			if slot.layer == layer_index {
				text_atlas_blit(&atlas, face, slot, rects[index])
			}
		}
	}

	if with_shaper {
		shaper, shaper_ok := text_shaper_init()
		if !shaper_ok {
			text_atlas_destroy(&atlas)
			return {}, false
		}
		atlas.shaper = shaper
	}

	log.debugf("text atlas: %dx%d, %d layers, %d glyph phases", atlas.width, atlas.height, atlas.count, len(slots))
	return atlas, true
}

@(private)
text_face_setup :: proc(face: font.Face, weight: u16, px: u32) -> bool {
	if face.face_flags & font.FACE_FLAG_MULTIPLE_MASTERS != 0 {
		coord := font.Fixed(f32(weight) * 65536.0)
		if font.Set_Var_Design_Coordinates(face, 1, &coord) != font.OK {
			log.errorf("text atlas: could not set weight %d", weight)
			return false
		}
	}
	if font.Set_Pixel_Sizes(face, 0, c.uint(px)) != font.OK {
		return false
	}
	return true
}

@(private)
text_glyph_render :: proc(face: font.Face, index: u32, phase: int) -> (bitmap: font.Bitmap, left, top: int, ok: bool) {
	if font.Load_Glyph(face, index, font.LOAD_NO_HINTING | font.LOAD_NO_BITMAP) != font.OK {
		return {}, 0, 0, false
	}
	slot := face.glyph
	if slot == nil {
		return {}, 0, 0, false
	}
	if slot.outline.n_points > 0 {
		shift := font.Pos((phase * 64) / TEXT_SUBPIXEL_PHASES)
		font.Outline_Translate(&slot.outline, shift, 0)
	}
	if font.Render_Glyph(slot, font.RENDER_MODE_NORMAL) != font.OK {
		return {}, 0, 0, false
	}
	bitmap = slot.bitmap
	if bitmap.rows == 0 || bitmap.width == 0 || bitmap.pixel_mode != font.PIXEL_MODE_GRAY {
		return {}, 0, 0, false
	}
	return bitmap, int(slot.bitmap_left), -int(slot.bitmap_top), true
}

@(private)
text_glyph_cell :: proc(slot: Text_Glyph_Slot) -> [2]int {
	return {
		slot.width + TEXT_GLYPH_PADDING * 2,
		slot.height + TEXT_GLYPH_PADDING * 2,
	}
}

@(private)
text_layer_metrics :: proc(layer: ^Text_Layer, face: font.Face, px: u32) {
	upem := f32(face.units_per_em)
	scale := f32(px) / upem
	layer.ascent = f32(face.ascender) * scale
	layer.descent = f32(face.descender) * scale
	layer.line_gap = f32(face.height - (face.ascender - face.descender)) * scale
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
text_atlas_blit :: proc(atlas: ^Text_Atlas, face: font.Face, slot: Text_Glyph_Slot, rect: stbrp.Rect) {
	bitmap, left, top, rendered := text_glyph_render(face, u32(slot.index), slot.phase)
	if !rendered {
		return
	}
	cell_w := int(bitmap.width) + TEXT_GLYPH_PADDING * 2
	cell_h := int(bitmap.rows) + TEXT_GLYPH_PADDING * 2
	x := int(rect.x) + TEXT_GLYPH_PADDING
	y := int(rect.y) + TEXT_GLYPH_PADDING
	width := int(bitmap.width)
	pitch := int(bitmap.pitch)
	for row in 0 ..< int(bitmap.rows) {
		src := bitmap.buffer[row * pitch :][:width]
		dst := atlas.pixels[(y + row) * int(atlas.width) + x :][:width]
		copy(dst, src)
	}

	glyph := &atlas.layers[slot.layer].glyphs[slot.index]
	glyph.phases[slot.phase] = {
		uv = {
			f32(rect.x) / f32(atlas.width),
			f32(rect.y) / f32(atlas.height),
			f32(int(rect.x) + cell_w) / f32(atlas.width),
			f32(int(rect.y) + cell_h) / f32(atlas.height),
		},
		offset = {f32(left - TEXT_GLYPH_PADDING), f32(top - TEXT_GLYPH_PADDING)},
		size = {f32(cell_w), f32(cell_h)},
	}
	glyph.present = true
}
