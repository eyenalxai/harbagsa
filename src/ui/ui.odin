// The vocabulary the simulation and the renderer share. It holds data only, so
// the game never imports the renderer and the renderer never imports the game.
package ui

TYPE_WEIGHT_MIN :: f32(100)
TYPE_WEIGHT_MAX :: f32(900)
TYPE_WEIGHT_DEFAULT :: f32(400)

Row_Kind :: enum {
	Setting,
	Action,
	Metric,
	Detail,
	Slider,
	Divider,
	Header,
}

Row_Align :: enum {
	Left,
	Right,
}

Row :: struct {
	kind:    Row_Kind,
	label:   string,
	value:   string,
	numeric: bool,
	blocked: bool,
	ratio:   f32,
	ticks:   int,
}

Hint_Cell :: struct {
	keys:   string,
	action: string,
}

Menu :: struct {
	title:    string,
	rows:     []Row,
	selected: int,
	hints:        []Hint_Cell,
	hint_columns: int,
	note:         string,
}

PALETTE_MAX_ITEMS :: 12
PALETTE_MAX_HINTS :: 8
PALETTE_TEXT_BYTES :: 40

Palette_Item :: struct {
	name:         string,
	short_name:   string,
	half_extents: [3]f32,
	color:        [4]f32,
	base_pitch:   f32,
	body:         string,
	key:          string,
	light_line:   [PALETTE_TEXT_BYTES]u8,
	light_length: int,
	emissive:     bool,
}

// A palette travels by value through HUD_Frame, so the items, hints, and
// formatted text live inside the struct; a slice would point at the old copy.
Palette :: struct {
	open:         bool,
	title:        string,
	items:        [PALETTE_MAX_ITEMS]Palette_Item,
	item_count:   int,
	selected:     int,
	body:         string,
	size:         [PALETTE_TEXT_BYTES]u8,
	size_length:  int,
	count:        [PALETTE_TEXT_BYTES]u8,
	count_length: int,
	hints:        [PALETTE_MAX_HINTS]Hint_Cell,
	hint_count:   int,
}

// A notice is one line about an action whose result is not on screen. It is not
// a row: it appears, holds, and leaves, while the rows stay put.
Notice :: struct {
	text: string,
}

Hud :: struct {
	rows:   []Row,
	notice: Notice,
}

Slider_Rect :: struct {
	x, y, width, height: f32,
	knob:                f32,
}

// `inside` uses the full track, so a press on either knob end starts a drag.
// The ratio maps the travel between the knob centers.
slider_hit :: proc(rect: Slider_Rect, point: [2]f32) -> (ratio: f32, inside: bool) {
	if rect.width <= 0 || rect.height <= 0 {
		return 0, false
	}
	inside =
		point.x >= rect.x &&
		point.x <= rect.x + rect.width &&
		point.y >= rect.y &&
		point.y <= rect.y + rect.height
	knob := clamp(rect.knob, 0, rect.width)
	travel := rect.width - knob
	if travel <= 0 {
		return 0, inside
	}
	ratio = clamp((point.x - (rect.x + knob * 0.5)) / travel, 0, 1)
	return ratio, inside
}
