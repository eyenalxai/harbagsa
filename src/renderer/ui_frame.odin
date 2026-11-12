#+vet explicit-allocators
package renderer

import "src:ui"

UI_Key :: enum {
	Up,
	Down,
	Left,
	Right,
	Confirm,
	Escape,
}

UI_KEYS :: bit_set[UI_Key]

UI_Action_Kind :: enum(u32) {
	Close_Menu     = 1,
	Toggle_Debug   = 2,
	Palette_Select = 3,
}

// One flat frame for the Rust shim. The shim copies it into its own Rune state,
// so every string here must stay valid for the ui_frame call only.
UI_Frame :: struct {
	dt:              f64,
	snapshot:        Ui_Snapshot,
	pointer:         [2]f32,
	pointer_pressed: bool,
	pointer_down:    bool,
	keys:            UI_KEYS,
	panel_rows:      []ui.Row,
	notice:          string,
	capture_hint:    string,
	captured:        bool,
	palette_open:    bool,
	menu:            ui.Menu,
	palette:         ui.Palette,
}

HUD_Frame :: struct {
	enabled: bool,
	ui:      UI_Frame,
}
