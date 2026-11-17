#+vet explicit-allocators
package platform

import "core:c"
import "core:log"
import "core:math"
import "vendor:sdl3"

GAMEPAD_DEADZONE :: f32(0.15)

Gamepad_Button :: enum(u8) {
	South,
	East,
	West,
	North,
	Back,
	Start,
	Left_Stick,
	Right_Stick,
	Left_Shoulder,
	Right_Shoulder,
	Dpad_Up,
	Dpad_Down,
	Dpad_Left,
	Dpad_Right,
}

Gamepad_Buttons :: bit_set[Gamepad_Button]

// Gamepad_State is one frame of the first gamepad: the button edges from the
// event queue and the two sticks.
Gamepad_State :: struct {
	connected: bool,
	pressed:   Gamepad_Buttons,
	released:  Gamepad_Buttons,
	left:      [2]f32,
	right:     [2]f32,
}

// Gamepad_Device is the open handle and the previous held set. Hot-plug is not
// handled: the first gamepad present at startup is the one the session uses.
Gamepad_Device :: struct {
	handle:    ^sdl3.Gamepad,
	held:      Gamepad_Buttons,
	connected: bool,
}

gamepad_open :: proc(device: ^Gamepad_Device) {
	count: c.int
	ids := sdl3.GetGamepads(&count)
	if ids == nil || count <= 0 {
		return
	}
	device.handle = sdl3.OpenGamepad(ids[0])
	if device.handle == nil {
		log.warnf("platform: SDL_OpenGamepad failed: %v", sdl3.GetError())
	}
}

gamepad_close :: proc(device: ^Gamepad_Device) {
	if device.handle != nil {
		sdl3.CloseGamepad(device.handle)
	}
	device^ = {}
}

gamepad_read :: proc(device: ^Gamepad_Device, state: ^Gamepad_State) {
	if device.handle == nil {
		if device.connected {
			log.warn("platform: the gamepad disconnected")
			device.connected = false
			device.held = {}
		}
		return
	}
	if !sdl3.GamepadConnected(device.handle) {
		if device.connected {
			log.warn("platform: the gamepad disconnected")
		}
		device.connected = false
		device.held = {}
		return
	}
	state.connected = true
	device.connected = true
	state.left = {
		stick_axis(sdl3.GetGamepadAxis(device.handle, .LEFTX)),
		stick_axis(sdl3.GetGamepadAxis(device.handle, .LEFTY)),
	}
	state.right = {
		stick_axis(sdl3.GetGamepadAxis(device.handle, .RIGHTX)),
		stick_axis(sdl3.GetGamepadAxis(device.handle, .RIGHTY)),
	}
}

// gamepad_button_event keeps the press and release edges from SDL's event
// queue, so a tap between polls is not lost.
gamepad_button_event :: proc(
	device: ^Gamepad_Device,
	state: ^Gamepad_State,
	button: Gamepad_Button,
	down: bool,
) {
	if down {
		if button not_in device.held {
			device.held += {button}
			state.pressed += {button}
		}
	} else if button in device.held {
		device.held -= {button}
		state.released += {button}
	}
}

@(private)
stick_axis :: proc(raw: i16) -> f32 {
	value := clamp(f32(raw) / 32767.0, -1.0, 1.0)
	if math.abs(value) <= GAMEPAD_DEADZONE {
		return 0.0
	}
	sign: f32 = value < 0.0 ? -1.0 : 1.0
	return sign * (math.abs(value) - GAMEPAD_DEADZONE) / (1.0 - GAMEPAD_DEADZONE)
}

@(private)
gamepad_button_from_sdl :: proc(button: sdl3.GamepadButton) -> (Gamepad_Button, bool) {
	#partial switch button {
	case .SOUTH:
		return .South, true
	case .EAST:
		return .East, true
	case .WEST:
		return .West, true
	case .NORTH:
		return .North, true
	case .BACK:
		return .Back, true
	case .START:
		return .Start, true
	case .LEFT_STICK:
		return .Left_Stick, true
	case .RIGHT_STICK:
		return .Right_Stick, true
	case .LEFT_SHOULDER:
		return .Left_Shoulder, true
	case .RIGHT_SHOULDER:
		return .Right_Shoulder, true
	case .DPAD_UP:
		return .Dpad_Up, true
	case .DPAD_DOWN:
		return .Dpad_Down, true
	case .DPAD_LEFT:
		return .Dpad_Left, true
	case .DPAD_RIGHT:
		return .Dpad_Right, true
	}
	return .South, false
}
