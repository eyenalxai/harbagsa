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

// Gamepad_State is one frame of the first gamepad: the held buttons, the edges
// since the last frame, and the two sticks. Button edges are the only events;
// the sticks are held state like the keyboard movement axes.
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
	state^ = {}
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
	device.connected = true
	held := Gamepad_Buttons{}
	for button in Gamepad_Button {
		if sdl3.GetGamepadButton(device.handle, sdl_button(button)) {
			held += {button}
		}
	}
	state.connected = true
	state.pressed = held &~ device.held
	state.released = device.held &~ held
	state.left = {
		stick_axis(sdl3.GetGamepadAxis(device.handle, .LEFTX)),
		stick_axis(sdl3.GetGamepadAxis(device.handle, .LEFTY)),
	}
	state.right = {
		stick_axis(sdl3.GetGamepadAxis(device.handle, .RIGHTX)),
		stick_axis(sdl3.GetGamepadAxis(device.handle, .RIGHTY)),
	}
	device.held = held
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
sdl_button :: proc(button: Gamepad_Button) -> sdl3.GamepadButton {
	switch button {
	case .South:
		return .SOUTH
	case .East:
		return .EAST
	case .West:
		return .WEST
	case .North:
		return .NORTH
	case .Back:
		return .BACK
	case .Start:
		return .START
	case .Left_Stick:
		return .LEFT_STICK
	case .Right_Stick:
		return .RIGHT_STICK
	case .Left_Shoulder:
		return .LEFT_SHOULDER
	case .Right_Shoulder:
		return .RIGHT_SHOULDER
	case .Dpad_Up:
		return .DPAD_UP
	case .Dpad_Down:
		return .DPAD_DOWN
	case .Dpad_Left:
		return .DPAD_LEFT
	case .Dpad_Right:
		return .DPAD_RIGHT
	}
	return .INVALID
}
