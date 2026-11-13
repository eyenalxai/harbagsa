// The vocabulary the simulation and the renderer share. It holds data only, so
// the game never imports the renderer and the renderer never imports the game.
package ui

TYPE_WEIGHT_MIN :: f32(100)
TYPE_WEIGHT_MAX :: f32(900)
TYPE_WEIGHT_DEFAULT :: f32(400)

HUD_OPACITY_MIN :: f32(0.70)
HUD_OPACITY_MAX :: f32(1.00)
HUD_OPACITY_DEFAULT :: f32(0.94)
// Below this the tertiary ink no longer holds the text floor on the HUD.
HUD_OPACITY_PROMOTE :: f32(0.94)

SETTINGS_MAX_DISPLAYS :: 8
SETTINGS_MAX_MODES :: 64
SETTINGS_OPTION_BYTES :: 32
SETTINGS_HINT_COUNT :: 6

Row_Kind :: enum {
	Setting,
	Action,
	Metric,
	Detail,
	Divider = 5,
	Header  = 6,
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
}

Hint_Cell :: struct {
	keys:   string,
	action: string,
}

Menu :: struct {
	title: string,
	hints: []Hint_Cell,
	note:  string,
}

Settings_Option :: struct {
	text:   [SETTINGS_OPTION_BYTES]u8,
	length: int,
}

// The settings dialog's values and option names. The menu snapshot carries its
// title, description, and hints; this carries the controls.
Settings :: struct {
	window_modes:     [2]Settings_Option,
	window_mode:      int,
	display_names:    [SETTINGS_MAX_DISPLAYS]Settings_Option,
	display:          int,
	display_count:    int,
	resolution_names:   [SETTINGS_MAX_MODES]Settings_Option,
	resolution:         int,
	resolution_count:   int,
	resolution_current: Settings_Option,
	resolution_missing: bool,
	sprint_modes:       [2]Settings_Option,
	sprint_mode:      int,
	hud_opacity:      f32,
	reduce_motion:    bool,
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
