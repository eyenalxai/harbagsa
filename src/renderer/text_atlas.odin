#+vet explicit-allocators
#+vet !unused-procedures // the atlas uses every key helper
package renderer

import "core:log"
import "core:math"
import "core:mem"

import "src:ui"

GEIST :: #load("fonts/Geist-Variable.ttf")
GEIST_MONO :: #load("fonts/GeistMono-Variable.ttf")

// Glyphs rasterize at the device pixel size, so the atlas is a coverage map and
// not a distance field. Four horizontal phases cover the sub-pixel positions a
// layout produces.
TEXT_SUBPIXEL_PHASES :: 4
TEXT_GLYPH_PADDING :: 1
TEXT_LAYER_MAX :: 8
TEXT_ATLAS_MIN_SIDE :: 256
TEXT_ATLAS_MAX_SIDE :: 4096
TEXT_ATLAS_SIDE_STEP :: 256
TEXT_ATLAS_PACK_HEADROOM :: 1.5

BASE_WEIGHT :: ui.TYPE_WEIGHT_DEFAULT
MIN_WEIGHT :: ui.TYPE_WEIGHT_MIN
MAX_WEIGHT :: ui.TYPE_WEIGHT_MAX

Text_Face :: enum {
	Sans,
	Mono,
}

TEXT_FACE_COUNT :: len(Text_Face)

// The rasterization key. Two styles share a layer when the face, the weight,
// and the pixel size match.
Text_Layer_Key :: struct {
	face:   Text_Face,
	weight: u16,
	px:     u32,
}

Text_Glyph_Phase :: struct {
	uv:     [4]f32,
	offset: [2]f32,
	size:   [2]f32,
}

Text_Glyph :: struct {
	phases:  [TEXT_SUBPIXEL_PHASES]Text_Glyph_Phase,
	present: bool,
}

Text_Layer :: struct {
	key:      Text_Layer_Key,
	ascent:   f32,
	descent:  f32,
	line_gap: f32,
	glyphs:   []Text_Glyph,
}

// Every layer a theme can draw, sorted and de-duplicated so a rebuild is a
// straight comparison.
Text_Layer_Set :: struct {
	keys:  [TEXT_LAYER_MAX]Text_Layer_Key,
	count: int,
}

// A silent cap turns a text bug into a layout bug, so the atlas counts the
// truncations and the dropped fonts it had to make and the harness reads them.
Text_Caps :: struct {
	truncated_runs: int,
	dropped_fonts:  int,
	warned:         bool,
}

Text_Atlas :: struct {
	width:  u32,
	height: u32,
	pixels: []u8,
	layers: [TEXT_LAYER_MAX]Text_Layer,
	count:  int,
	shaper: Text_Shaper,
	caps:   Text_Caps,
	allocator: mem.Allocator,
}

TEXT_FONTS := [TEXT_FACE_COUNT][]u8 {
	GEIST,
	GEIST_MONO,
}

text_face_data :: proc(face: Text_Face) -> []u8 {
	return TEXT_FONTS[int(face)]
}

// A weight is a whole unit on the axis. FreeType and HarfBuzz accept the value
// as a float, but the atlas keys and the settings row only need integers.
text_weight_key :: proc(weight: f32) -> u16 {
	return u16(math.round(clamp(weight, MIN_WEIGHT, MAX_WEIGHT)))
}

@(private)
text_layer_key_less :: proc(a, b: Text_Layer_Key) -> bool {
	if a.face != b.face {
		return a.face < b.face
	}
	if a.weight != b.weight {
		return a.weight < b.weight
	}
	return a.px < b.px
}

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

text_layer_set_equal :: proc(a, b: Text_Layer_Set) -> bool {
	if a.count != b.count {
		return false
	}
	for index in 0 ..< a.count {
		if a.keys[index] != b.keys[index] {
			return false
		}
	}
	return true
}

text_atlas_destroy :: proc(atlas: ^Text_Atlas) {
	allocator := atlas.allocator
	if atlas.pixels != nil {
		delete(atlas.pixels, allocator)
		atlas.pixels = nil
	}
	for &layer in atlas.layers[:atlas.count] {
		if layer.glyphs != nil {
			delete(layer.glyphs, allocator)
			layer.glyphs = nil
		}
	}
	text_shaper_destroy(&atlas.shaper)
	atlas.allocator = {}
	atlas.count = 0
	atlas.width = 0
	atlas.height = 0
}
