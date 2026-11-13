#+vet explicit-allocators
package renderer

import "src:ui"

UI_Action_Kind :: enum(u32) {
	Close_Menu       = 1,
	Toggle_Debug     = 2,
	Palette_Select   = 3,
	Palette_Close    = 4,
	Settings_Set     = 5,
	Type_Weight_Set  = 6,
	Palette_Pick     = 7,
	Object_Set       = 8,
	Object_Toggle    = 9,
	Object_Duplicate = 10,
	Object_Delete    = 11,
	Lamp_Set         = 12,
	Lamp_Kind        = 13,
	Lamp_Color       = 14,
	Toggle_Inspector = 15,
	Open_Menu         = 16,
}

UI_Settings_Id :: enum(u32) {
	Window_Mode,
	Display,
	Resolution,
	Sprint_Mode,
	Hud_Opacity,
	Reduce_Motion,
}

UI_Object_Field :: enum(u32) {
	Body,
	Yaw,
}

UI_Lamp_Field :: enum(u32) {
	Kind,
	Color,
	Intensity,
	Range,
}

UI_EVENT_POINTER_MOVE :: u32(1)
UI_EVENT_POINTER_DOWN :: u32(2)
UI_EVENT_POINTER_UP :: u32(3)
UI_EVENT_POINTER_LEAVE :: u32(4)
UI_EVENT_WHEEL :: u32(7)
UI_EVENT_KEY_DOWN :: u32(8)
UI_EVENT_KEY_UP :: u32(9)
UI_EVENT_KEY_REPEAT :: u32(10)
UI_EVENT_FOCUS :: u32(11)

UI_KEY_NONE :: i32(0)
UI_KEY_UP :: i32(1)
UI_KEY_DOWN :: i32(2)
UI_KEY_LEFT :: i32(3)
UI_KEY_RIGHT :: i32(4)
UI_KEY_ENTER :: i32(5)
UI_KEY_ESCAPE :: i32(6)
UI_KEY_TAB :: i32(7)
UI_KEY_SPACE :: i32(8)

// One Rune input event. Pointer coordinates are normalized to the target and
// converted to points in ui_step; key and focus events ignore them.
UI_Event :: struct {
	kind:  u32,
	flags: u32,
	x:     f32,
	y:     f32,
	dx:    f32,
	dy:    f32,
	key:   i32,
}

// One flat frame for the Rust shim. The shim copies it into its own Rune state,
// so every string here must stay valid for the ui_frame call only.
UI_Frame :: struct {
	dt:           f64,
	snapshot:     Ui_Snapshot,
	events:       []UI_Event,
	panel_rows:   []ui.Row,
	notice:       string,
	capture_hint: string,
	captured:     bool,
	palette_open: bool,
	menu:         ui.Menu,
	settings:     ui.Settings,
	palette:      ui.Palette,
}

HUD_Frame :: struct {
	enabled: bool,
	weight:  f32,
	ui:      UI_Frame,
}
