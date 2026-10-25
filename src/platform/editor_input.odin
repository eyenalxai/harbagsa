#+vet explicit-allocators
package platform

import "vendor:sdl3"

// Key is the platform's name for a key edge. The SDL scancode stops here; the
// game layer never sees an SDL type.
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
	D,
	Z,
	Space,
	R,
	LShift,
	F1,
	F2,
	F3,
	F4,
	F5,
	Digit_1,
	Digit_2,
	Digit_3,
	Digit_4,
	Digit_5,
	Digit_6,
	Digit_7,
	Digit_8,
	Digit_9,
}

Modifier :: enum {
	Shift,
	Ctrl,
}

Modifiers :: bit_set[Modifier]

key_from_scancode :: proc(scancode: sdl3.Scancode) -> Key {
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
	case .D:
		return .D
	case .Z:
		return .Z
	case .SPACE:
		return .Space
	case .R:
		return .R
	case .LSHIFT:
		return .LShift
	case .F1:
		return .F1
	case .F2:
		return .F2
	case .F3:
		return .F3
	case .F4:
		return .F4
	case .F5:
		return .F5
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
	}
	return .None
}

modifiers_from_sdl :: proc(mod: sdl3.Keymod) -> Modifiers {
	mods: Modifiers
	if .LSHIFT in mod || .RSHIFT in mod {
		mods |= {.Shift}
	}
	if .LCTRL in mod || .RCTRL in mod {
		mods |= {.Ctrl}
	}
	return mods
}

normalize_pointer :: proc(x, y, width, height: f32) -> [2]f32 {
	if width <= 0.0 || height <= 0.0 {
		return {}
	}
	return {x / width, y / height}
}
