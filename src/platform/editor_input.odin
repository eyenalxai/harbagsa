#+vet explicit-allocators
package platform

import "vendor:sdl3"

// The key-to-action map is platform independent so it can be tested without a
// window. The scancode and modifier adapters at the end translate the SDL edges
// into that map.
Key :: enum {
	None,
	Tab,
	Q,
	E,
	G,
	M,
	L,
	C,
	Left_Bracket,
	Right_Bracket,
	Comma,
	Period,
	Up,
	Down,
	Left,
	Right,
	Enter,
	Escape,
	Delete,
	X,
	Digit_1,
	Digit_2,
	Digit_3,
	Digit_4,
	Digit_5,
	Digit_6,
	Digit_7,
	Digit_8,
	Digit_9,
	D,
	Z,
}

Modifier :: enum {
	Shift,
	Ctrl,
}

Modifiers :: bit_set[Modifier]

Editor_Action :: enum {
	None,
	Toggle_Palette,
	Navigate_Up,
	Navigate_Down,
	Navigate_Left,
	Navigate_Right,
	Confirm,
	Select_Card,
	Flip_Body,
	Toggle_Snap,
	Rotate_Left,
	Rotate_Right,
	Sun_Placement,
	Light_Color,
	Light_Intensity_Down,
	Light_Intensity_Up,
	Light_Range_Down,
	Light_Range_Up,
	Duplicate,
	Undo,
	Redo,
	Delete,
	Cancel,
}

Editor_Command :: struct {
	action: Editor_Action,
	index:  int,
}

editor_command :: proc(key: Key, mods: Modifiers) -> Editor_Command {
	switch key {
	case .None:
		return {}
	case .Tab:
		return {action = .Toggle_Palette}
	case .Up:
		return {action = .Navigate_Up}
	case .Down:
		return {action = .Navigate_Down}
	case .Left:
		return {action = .Navigate_Left}
	case .Right:
		return {action = .Navigate_Right}
	case .Enter:
		return {action = .Confirm}
	case .Digit_1:
		return {action = .Select_Card, index = 1}
	case .Digit_2:
		return {action = .Select_Card, index = 2}
	case .Digit_3:
		return {action = .Select_Card, index = 3}
	case .Digit_4:
		return {action = .Select_Card, index = 4}
	case .Digit_5:
		return {action = .Select_Card, index = 5}
	case .Digit_6:
		return {action = .Select_Card, index = 6}
	case .Digit_7:
		return {action = .Select_Card, index = 7}
	case .Digit_8:
		return {action = .Select_Card, index = 8}
	case .Digit_9:
		return {action = .Select_Card, index = 9}
	case .M:
		return {action = .Flip_Body}
	case .G:
		return {action = .Toggle_Snap}
	case .Q:
		return {action = .Rotate_Left}
	case .E:
		return {action = .Rotate_Right}
	case .L:
		return {action = .Sun_Placement}
	case .C:
		return {action = .Light_Color}
	case .Left_Bracket:
		return {action = .Light_Intensity_Down}
	case .Right_Bracket:
		return {action = .Light_Intensity_Up}
	case .Comma:
		return {action = .Light_Range_Down}
	case .Period:
		return {action = .Light_Range_Up}
	case .Delete, .X:
		return {action = .Delete}
	case .Escape:
		return {action = .Cancel}
	case .D:
		if .Ctrl in mods {
			return {action = .Duplicate}
		}
	case .Z:
		if .Ctrl in mods {
			if .Shift in mods {
				return {action = .Redo}
			}
			return {action = .Undo}
		}
	}
	return {}
}

normalize_pointer :: proc(x, y, width, height: f32) -> [2]f32 {
	if width <= 0.0 || height <= 0.0 {
		return {}
	}
	return {x / width, y / height}
}

@(private)
apply_editor_command :: proc(events: ^Events, command: Editor_Command) {
	switch command.action {
	case .None:
	case .Toggle_Palette:
		events.palette_toggle_pressed = true
	case .Navigate_Up:
		events.navigate_up_pressed = true
	case .Navigate_Down:
		events.navigate_down_pressed = true
	case .Navigate_Left:
		events.navigate_left_pressed = true
	case .Navigate_Right:
		events.navigate_right_pressed = true
	case .Confirm:
		events.confirm_pressed = true
	case .Select_Card:
		events.palette_number = command.index
	case .Flip_Body:
		events.flip_body_pressed = true
	case .Toggle_Snap:
		events.toggle_snap_pressed = true
	case .Rotate_Left:
		events.rotate_left_pressed = true
	case .Rotate_Right:
		events.rotate_right_pressed = true
	case .Sun_Placement:
		events.sun_pressed = true
		events.sun_placement_pressed = true
	case .Light_Color:
		events.light_color_pressed = true
	case .Light_Intensity_Down:
		events.light_intensity_down_pressed = true
	case .Light_Intensity_Up:
		events.light_intensity_up_pressed = true
	case .Light_Range_Down:
		events.light_range_down_pressed = true
	case .Light_Range_Up:
		events.light_range_up_pressed = true
	case .Duplicate:
		events.duplicate_pressed = true
	case .Undo:
		events.undo_pressed = true
	case .Redo:
		events.redo_pressed = true
	case .Delete:
		events.delete_pressed = true
	case .Cancel:
		events.cancel_pressed = true
	}
}

@(private)
editor_key_from_scancode :: proc(scancode: sdl3.Scancode) -> Key {
	#partial switch scancode {
	case .TAB:
		return .Tab
	case .Q:
		return .Q
	case .E:
		return .E
	case .G:
		return .G
	case .M:
		return .M
	case .L:
		return .L
	case .C:
		return .C
	case .LEFTBRACKET:
		return .Left_Bracket
	case .RIGHTBRACKET:
		return .Right_Bracket
	case .COMMA:
		return .Comma
	case .PERIOD:
		return .Period
	case .UP:
		return .Up
	case .DOWN:
		return .Down
	case .LEFT:
		return .Left
	case .RIGHT:
		return .Right
	case .RETURN, .KP_ENTER:
		return .Enter
	case .ESCAPE:
		return .Escape
	case .DELETE:
		return .Delete
	case .X:
		return .X
	case ._1:
		return .Digit_1
	case ._2:
		return .Digit_2
	case ._3:
		return .Digit_3
	case ._4:
		return .Digit_4
	case ._5:
		return .Digit_5
	case ._6:
		return .Digit_6
	case ._7:
		return .Digit_7
	case ._8:
		return .Digit_8
	case ._9:
		return .Digit_9
	case .D:
		return .D
	case .Z:
		return .Z
	}
	return .None
}

@(private)
editor_modifiers :: proc(mod: sdl3.Keymod) -> Modifiers {
	mods: Modifiers
	if .LSHIFT in mod || .RSHIFT in mod {
		mods |= {.Shift}
	}
	if .LCTRL in mod || .RCTRL in mod {
		mods |= {.Ctrl}
	}
	return mods
}
