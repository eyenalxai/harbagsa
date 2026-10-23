#+vet explicit-allocators
package platform

import "core:c"
import "core:log"
import "vendor:sdl3"
import vk "vendor:vulkan"

// Window and event handling backed by SDL3, plus the SDL3 Vulkan surface
// helpers. The renderer owns every Vulkan object; this module only creates the
// window, hands out the instance extension list, and makes the surface.

Error :: enum {
	None,
	SDL_Init,
	Create_Window,
	Vulkan_Extensions,
	Create_Surface,
}

Window :: struct {
	handle: ^sdl3.Window,
}

// One frame of window and player input. Movement axes come from the keyboard
// state while the cursor is captured. look_delta is the relative mouse motion
// accumulated since the previous poll. jump_pressed and reset_pressed are true
// only on the key-down edge, so a held key does not repeat them.
Events :: struct {
	quit:          bool,
	move_forward:  f32,
	move_right:    f32,
	look_delta:    [2]f32,
	jump_pressed:  bool,
	reset_pressed: bool,
	captured:      bool,
}

init :: proc(title: cstring, width, height: i32) -> (window: Window, err: Error) {
	if !sdl3.Init({.VIDEO}) {
		log.errorf("platform: SDL_Init failed: %v", sdl3.GetError())
		return {}, .SDL_Init
	}

	window.handle = sdl3.CreateWindow(title, width, height, {.VULKAN, .RESIZABLE})
	if window.handle == nil {
		log.errorf("platform: SDL_CreateWindow failed: %v", sdl3.GetError())
		sdl3.Quit()
		return {}, .Create_Window
	}

	return window, .None
}

deinit :: proc(window: ^Window) {
	if window.handle != nil {
		sdl3.DestroyWindow(window.handle)
		window.handle = nil
	}
	sdl3.Quit()
}

// vulkan_loader_proc returns vkGetInstanceProcAddr from the Vulkan loader that
// SDL opened for the window.
vulkan_loader_proc :: proc() -> rawptr {
	return rawptr(sdl3.Vulkan_GetVkGetInstanceProcAddr())
}

// vulkan_extensions returns the instance extensions that the window needs.
// The slice points into SDL-owned storage and stays valid for the window's
// lifetime.
vulkan_extensions :: proc() -> (extensions: []cstring, err: Error) {
	count: u32
	names := sdl3.Vulkan_GetInstanceExtensions(&count)
	if names == nil || count == 0 {
		log.errorf("platform: SDL_Vulkan_GetInstanceExtensions failed: %v", sdl3.GetError())
		return nil, .Vulkan_Extensions
	}
	return names[:count], .None
}

create_vulkan_surface :: proc(window: ^Window, instance: vk.Instance) -> (surface: vk.SurfaceKHR, err: Error) {
	if !sdl3.Vulkan_CreateSurface(window.handle, instance, nil, &surface) {
		log.errorf("platform: SDL_Vulkan_CreateSurface failed: %v", sdl3.GetError())
		return 0, .Create_Surface
	}
	return surface, .None
}

destroy_vulkan_surface :: proc(instance: vk.Instance, surface: vk.SurfaceKHR) {
	sdl3.Vulkan_DestroySurface(instance, surface, nil)
}

poll_events :: proc(window: ^Window) -> (events: Events) {
	return drain_events(window, nil)
}

// wait_events blocks until one event arrives or the timeout expires, then
// drains the queue. The main loop uses it while the window is minimized so the
// process does not spin.
wait_events :: proc(window: ^Window, timeout_ms: i32) -> (events: Events) {
	event: sdl3.Event
	if !sdl3.WaitEventTimeout(&event, timeout_ms) {
		return poll_events(window)
	}
	return drain_events(window, &event)
}

drain_events :: proc(window: ^Window, first: ^sdl3.Event) -> (events: Events) {
	events.captured = sdl3.GetWindowRelativeMouseMode(window.handle)
	if first != nil {
		apply_event(&events, first, window)
	}

	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		apply_event(&events, &event, window)
	}

	if events.captured {
		read_movement(&events)
	}
	return
}

// read_movement samples the keyboard state after the event drain. Held keys
// move the player; a free cursor always gives zero movement.
read_movement :: proc(events: ^Events) {
	key_count: c.int
	keys := sdl3.GetKeyboardState(&key_count)
	if keys == nil {
		return
	}

	if keys[int(sdl3.Scancode.W)] {
		events.move_forward += 1.0
	}
	if keys[int(sdl3.Scancode.S)] {
		events.move_forward -= 1.0
	}
	if keys[int(sdl3.Scancode.D)] {
		events.move_right += 1.0
	}
	if keys[int(sdl3.Scancode.A)] {
		events.move_right -= 1.0
	}
}

is_minimized :: proc(window: ^Window) -> bool {
	return .MINIMIZED in sdl3.GetWindowFlags(window.handle)
}

// pixel_size returns the drawable size in pixels, or zero when the window has
// no drawable area (for example while minimized).
pixel_size :: proc(window: ^Window) -> (width, height: u32) {
	w, h: c.int
	if !sdl3.GetWindowSizeInPixels(window.handle, &w, &h) {
		log.errorf("platform: SDL_GetWindowSizeInPixels failed: %v", sdl3.GetError())
		return 0, 0
	}
	if w <= 0 || h <= 0 {
		return 0, 0
	}
	return u32(w), u32(h)
}

apply_event :: proc(events: ^Events, event: ^sdl3.Event, window: ^Window) {
	#partial switch event.type {
	case .QUIT, .WINDOW_CLOSE_REQUESTED:
		events.quit = true
	case .MOUSE_BUTTON_DOWN:
		if event.button.button == 1 {
			events.captured = set_capture(window, true)
		}
	case .KEY_DOWN:
		if event.key.repeat {
			return
		}
		#partial switch event.key.scancode {
		case .ESCAPE:
			if events.captured {
				events.captured = set_capture(window, false)
				events.look_delta = {}
			}
		case .SPACE:
			events.jump_pressed = true
		case .R:
			events.reset_pressed = true
		}
	case .MOUSE_MOTION:
		if events.captured {
			events.look_delta.x += event.motion.xrel
			events.look_delta.y += event.motion.yrel
		}
	}
}

set_capture :: proc(window: ^Window, enabled: bool) -> bool {
	if !sdl3.SetWindowRelativeMouseMode(window.handle, enabled) {
		log.errorf("platform: SDL_SetWindowRelativeMouseMode failed: %v", sdl3.GetError())
	}
	return sdl3.GetWindowRelativeMouseMode(window.handle)
}
