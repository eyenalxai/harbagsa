#+vet explicit-allocators
#+vet !unused-procedures // the text engine consumes the codepoint lookup
package renderer

import "core:c"
import "core:log"
import "core:mem"

import stbrp "vendor:stb/rect_pack"
import stbtt "vendor:stb/truetype"

NOTO_SANS_REGULAR :: #load("fonts/NotoSans-Regular.ttf")
NOTO_SANS_MEDIUM :: #load("fonts/NotoSans-Medium.ttf")
NOTO_SANS_MONO_REGULAR :: #load("fonts/NotoSansMono-Regular.ttf")

// The atlas rasterizes at 40 px. That is close enough to the largest title
// (42 px at the highest density, a 5% upscale) and gives the small sizes the
// tighter field grid they need: at 12.5 px a 48 px field is minified four
// times, which thins the stroke.
TEXT_ATLAS_BASE_PX :: 40.0
TEXT_ATLAS_PADDING :: 6
TEXT_ATLAS_ONEDGE :: 128
TEXT_ATLAS_DIST_SCALE :: 64.0
TEXT_ATLAS_WIDTH :: 1024
TEXT_ATLAS_HEIGHT :: 512

TEXT_ASCII_FIRST :: 0x20
TEXT_ASCII_LAST :: 0x7E
TEXT_ASCII_COUNT :: TEXT_ASCII_LAST - TEXT_ASCII_FIRST + 1
TEXT_CODEPOINT_COUNT :: TEXT_ASCII_COUNT + 2 // plus the middle dot and the multiplication sign

Text_Weight :: enum {
	Regular,
	Medium,
	Mono,
}

TEXT_WEIGHT_COUNT :: len(Text_Weight)

Text_Glyph :: struct {
	uv:      [4]f32,
	offset:  [2]f32,
	advance: f32,
	present: bool,
}

Text_Atlas :: struct {
	width:   u32,
	height:  u32,
	pixels:  []u8,
	base_px: f32,
	ascent:  f32,
	descent: f32,
	line_gap: f32,
	glyphs:  [TEXT_WEIGHT_COUNT][TEXT_CODEPOINT_COUNT]Text_Glyph,
	// Pairs are indexed by glyph index, not codepoint; a sparse map would cost
	// more to search than the 113 KB table costs to hold.
	kern: [TEXT_WEIGHT_COUNT][]f32,
}

text_codepoint_at :: proc(index: int) -> rune {
	if index < TEXT_ASCII_COUNT {
		return rune(TEXT_ASCII_FIRST + index)
	}
	switch index - TEXT_ASCII_COUNT {
	case 0:
		return 0x00B7
	case 1:
		return 0x00D7
	}
	return 0
}

text_codepoint_index :: proc(codepoint: rune) -> (index: int, ok: bool) {
	if codepoint >= TEXT_ASCII_FIRST && codepoint <= TEXT_ASCII_LAST {
		return int(codepoint - TEXT_ASCII_FIRST), true
	}
	switch codepoint {
	case 0x00B7:
		return TEXT_ASCII_COUNT, true
	case 0x00D7:
		return TEXT_ASCII_COUNT + 1, true
	}
	return 0, false
}

text_atlas_build :: proc(allocator: mem.Allocator) -> (atlas: Text_Atlas, ok: bool) {
	atlas.width = TEXT_ATLAS_WIDTH
	atlas.height = TEXT_ATLAS_HEIGHT
	atlas.base_px = TEXT_ATLAS_BASE_PX
	atlas.pixels = make([]u8, int(atlas.width * atlas.height), allocator)

	rects := make([]stbrp.Rect, TEXT_WEIGHT_COUNT * TEXT_CODEPOINT_COUNT, context.temp_allocator)
	defer delete(rects, context.temp_allocator)

	infos: [TEXT_WEIGHT_COUNT]stbtt.fontinfo
	scales: [TEXT_WEIGHT_COUNT]f32
	fonts := [TEXT_WEIGHT_COUNT][]byte {
		NOTO_SANS_REGULAR,
		NOTO_SANS_MEDIUM,
		NOTO_SANS_MONO_REGULAR,
	}
	for weight_index in 0 ..< TEXT_WEIGHT_COUNT {
		font := fonts[weight_index]
		if stbtt.InitFont(&infos[weight_index], raw_data(font), 0) == false {
			log.errorf("text atlas: could not parse the %v face", Text_Weight(weight_index))
			return {}, false
		}
		scales[weight_index] = stbtt.ScaleForPixelHeight(
			&infos[weight_index],
			TEXT_ATLAS_BASE_PX,
		)
	}

	ascent, descent, line_gap: c.int
	stbtt.GetFontVMetrics(&infos[0], &ascent, &descent, &line_gap)
	atlas.ascent = f32(ascent) * scales[0]
	atlas.descent = f32(descent) * scales[0]
	atlas.line_gap = f32(line_gap) * scales[0]

	for weight_index in 0 ..< TEXT_WEIGHT_COUNT {
		for index in 0 ..< TEXT_CODEPOINT_COUNT {
			codepoint := text_codepoint_at(index)
			box_w, box_h := text_glyph_box(&infos[weight_index], scales[weight_index], codepoint)
			slot := weight_index * TEXT_CODEPOINT_COUNT + index
			rects[slot] = stbrp.Rect {
				id = c.int(slot),
				w  = stbrp.Coord(box_w),
				h  = stbrp.Coord(box_h),
			}
		}
	}

	nodes := make([]stbrp.Node, TEXT_ATLAS_WIDTH, context.temp_allocator)
	defer delete(nodes, context.temp_allocator)
	context_pack: stbrp.Context
	stbrp.init_target(&context_pack, TEXT_ATLAS_WIDTH, TEXT_ATLAS_HEIGHT, raw_data(nodes), c.int(len(nodes)))
	if stbrp.pack_rects(&context_pack, raw_data(rects), c.int(len(rects))) != 1 {
		log.error("text atlas: the glyphs did not fit")
		return {}, false
	}

	packed_area := 0
	for weight_index in 0 ..< TEXT_WEIGHT_COUNT {
		for index in 0 ..< TEXT_CODEPOINT_COUNT {
			rect := rects[weight_index * TEXT_CODEPOINT_COUNT + index]
			if !rect.was_packed {
				log.errorf("text atlas: glyph %d of %v did not pack", index, Text_Weight(weight_index))
				return {}, false
			}
			glyph := text_atlas_glyph(
				&infos[weight_index],
				scales[weight_index],
				index,
				rect,
				atlas,
			)
			atlas.glyphs[weight_index][index] = glyph
			packed_area += int(rect.w) * int(rect.h)
		}
	}

	for weight_index in 0 ..< TEXT_WEIGHT_COUNT {
		atlas.kern[weight_index] = make(
			[]f32,
			TEXT_CODEPOINT_COUNT * TEXT_CODEPOINT_COUNT,
			allocator,
		)
		for first in 0 ..< TEXT_CODEPOINT_COUNT {
			for second in 0 ..< TEXT_CODEPOINT_COUNT {
				advance := stbtt.GetCodepointKernAdvance(
					&infos[weight_index],
					text_codepoint_at(first),
					text_codepoint_at(second),
				)
				atlas.kern[weight_index][first * TEXT_CODEPOINT_COUNT + second] =
					f32(advance) * scales[weight_index]
			}
		}
	}

	log.infof(
		"text atlas: %dx%d, %d glyphs, %.0f%% occupancy",
		atlas.width,
		atlas.height,
		TEXT_WEIGHT_COUNT * TEXT_CODEPOINT_COUNT,
		f32(packed_area) / f32(atlas.width * atlas.height) * 100.0,
	)
	return atlas, true
}

text_atlas_destroy :: proc(atlas: ^Text_Atlas, allocator: mem.Allocator) {
	if atlas.pixels != nil {
		delete(atlas.pixels, allocator)
		atlas.pixels = nil
	}
	for weight_index in 0 ..< TEXT_WEIGHT_COUNT {
		if atlas.kern[weight_index] != nil {
			delete(atlas.kern[weight_index], allocator)
			atlas.kern[weight_index] = nil
		}
	}
}

@(private)
text_glyph_box :: proc(info: ^stbtt.fontinfo, scale: f32, codepoint: rune) -> (width, height: int) {
	x0, y0, x1, y1: c.int
	stbtt.GetCodepointBitmapBox(info, codepoint, scale, scale, &x0, &y0, &x1, &y1)
	width = max(int(x1 - x0), 1) + TEXT_ATLAS_PADDING * 2
	height = max(int(y1 - y0), 1) + TEXT_ATLAS_PADDING * 2
	return
}

@(private)
text_atlas_glyph :: proc(
	info: ^stbtt.fontinfo,
	scale: f32,
	index: int,
	rect: stbrp.Rect,
	atlas: Text_Atlas,
) -> Text_Glyph {
	glyph: Text_Glyph
	advance, bearing: c.int
	stbtt.GetCodepointHMetrics(info, text_codepoint_at(index), &advance, &bearing)
	glyph.advance = f32(advance) * scale

	bitmap_w, bitmap_h, offset_x, offset_y: c.int
	bitmap := stbtt.GetCodepointSDF(
		info,
		scale,
		c.int(text_codepoint_at(index)),
		TEXT_ATLAS_PADDING,
		TEXT_ATLAS_ONEDGE,
		TEXT_ATLAS_DIST_SCALE,
		&bitmap_w,
		&bitmap_h,
		&offset_x,
		&offset_y,
	)
	if bitmap == nil {
		return glyph
	}
	defer stbtt.FreeSDF(bitmap, nil)
	if bitmap_w <= 0 || bitmap_h <= 0 {
		return glyph
	}

	width := int(atlas.width)
	row_bytes := int(bitmap_w)
	for row in 0 ..< int(bitmap_h) {
		source := rawptr(uintptr(bitmap) + uintptr(row * row_bytes))
		target := (int(rect.y) + row) * width + int(rect.x)
		mem.copy(&atlas.pixels[target], source, row_bytes)
	}

	glyph.present = true
	glyph.offset = {f32(offset_x), f32(offset_y)}
	glyph.uv = {
		f32(rect.x) / f32(atlas.width),
		f32(rect.y) / f32(atlas.height),
		f32(int(rect.x) + row_bytes) / f32(atlas.width),
		f32(int(rect.y) + int(bitmap_h)) / f32(atlas.height),
	}
	return glyph
}
