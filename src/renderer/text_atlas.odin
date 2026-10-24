#+vet explicit-allocators
#+vet !unused-procedures // the text engine consumes the codepoint lookup
package renderer

import "core:log"
import "core:mem"

NOTO_SANS_REGULAR :: #load("fonts/NotoSans-Regular.ttf")
NOTO_SANS_MEDIUM :: #load("fonts/NotoSans-Medium.ttf")
NOTO_SANS_MONO_REGULAR :: #load("fonts/NotoSansMono-Regular.ttf")

// Glyphs rasterize at the device pixel size, so the atlas is a coverage map and
// not a distance field. A distance field cannot carry a stem thinner than the
// reconstruction footprint: at the caption size the stem is one pixel, its
// signed distance at the pixel centre never leaves the antialiasing ramp, and
// the stem draws grey and broken. Coverage has no such floor.
//
// Four horizontal phases cover the sub-pixel positions a layout produces. The
// phase is baked into the bitmap and the quad snaps to a whole pixel, so one
// texel lands on one pixel exactly.
TEXT_SUBPIXEL_PHASES :: 4
TEXT_GLYPH_PADDING :: 1
TEXT_LAYER_MAX :: 8
TEXT_ATLAS_MIN_SIDE :: 256
TEXT_ATLAS_MAX_SIDE :: 4096
TEXT_ATLAS_SIDE_STEP :: 256
TEXT_ATLAS_PACK_HEADROOM :: 1.5

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

TEXT_FONTS := [TEXT_WEIGHT_COUNT][]byte {
	NOTO_SANS_REGULAR,
	NOTO_SANS_MEDIUM,
	NOTO_SANS_MONO_REGULAR,
}

// The rasterization key. Two styles share a layer when the face and the pixel
// size match, which is what makes one atlas serve every role.
Text_Layer_Key :: struct {
	weight: Text_Weight,
	px:     u32,
}

Text_Glyph_Phase :: struct {
	uv:     [4]f32,
	offset: [2]f32,
	size:   [2]f32,
}

Text_Glyph :: struct {
	phases:  [TEXT_SUBPIXEL_PHASES]Text_Glyph_Phase,
	advance: f32,
	present: bool,
}

Text_Layer :: struct {
	key:      Text_Layer_Key,
	ascent:   f32,
	descent:  f32,
	line_gap: f32,
	glyphs:   [TEXT_CODEPOINT_COUNT]Text_Glyph,
	// Indexed by glyph index, not codepoint; a sparse map costs more to search
	// than the table costs to hold.
	kern: []f32,
}

// Every layer a theme can draw, sorted and de-duplicated so a rebuild is a
// straight comparison.
Text_Layer_Set :: struct {
	keys:  [TEXT_LAYER_MAX]Text_Layer_Key,
	count: int,
}

Text_Atlas :: struct {
	width:  u32,
	height: u32,
	pixels: []u8,
	layers: [TEXT_LAYER_MAX]Text_Layer,
	count:  int,
}

text_face :: proc(weight: Text_Weight) -> []byte {
	return TEXT_FONTS[int(weight)]
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

@(private)
text_layer_key_less :: proc(a, b: Text_Layer_Key) -> bool {
	if a.weight != b.weight {
		return a.weight < b.weight
	}
	return a.px < b.px
}

// Kept sorted so a rebuild is a straight comparison against a freshly derived
// set, whatever order the theme names its roles in.
text_layer_set_add :: proc(set: ^Text_Layer_Set, key: Text_Layer_Key) {
	if key.px == 0 {
		return
	}
	insert := set.count
	for other, index in set.keys[:set.count] {
		if other == key {
			return
		}
		if text_layer_key_less(key, other) {
			insert = index
			break
		}
	}
	if set.count >= TEXT_LAYER_MAX {
		log.warnf("text atlas: more than %d layers, dropping %v", TEXT_LAYER_MAX, key)
		return
	}
	for index := set.count; index > insert; index -= 1 {
		set.keys[index] = set.keys[index - 1]
	}
	set.keys[insert] = key
	set.count += 1
}

text_atlas_destroy :: proc(atlas: ^Text_Atlas, allocator: mem.Allocator) {
	if atlas.pixels != nil {
		delete(atlas.pixels, allocator)
		atlas.pixels = nil
	}
	for &layer in atlas.layers[:atlas.count] {
		if layer.kern != nil {
			delete(layer.kern, allocator)
			layer.kern = nil
		}
	}
	atlas.count = 0
	atlas.width = 0
	atlas.height = 0
}
