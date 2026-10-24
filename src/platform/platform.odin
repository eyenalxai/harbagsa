#+vet explicit-allocators
package platform

import "core:c"
import "core:log"
import "core:strings"
import "vendor:sdl3"
import vk "vendor:vulkan"

Error :: enum {
	None,
	SDL_Init,
	Create_Window,
	Vulkan_Extensions,
	Create_Surface,
}

Window :: struct {
	handle:           ^sdl3.Window,
	capture_on_click: bool,
}

// jump, reset, debug, the stance edges, and the editor actions are key-down
// edges so a held key does not repeat. The fly axes, movement keys, and the
// wheel are polled while captured.
Events :: struct {
	quit:                bool,
	resized:             bool,
	move_forward:        f32,
	move_right:          f32,
	sprint_held:         bool,
	sprint_pressed:      bool,
	crouch_held:         bool,
	crouch_pressed:      bool,
	prone_held:          bool,
	prone_pressed:       bool,
	look_delta:          [2]f32,
	wheel_delta:         f32,
	pointer:             [2]f32,
	pointer_down:        bool,
	pointer_pressed:     bool,
	pointer_released:    bool,
	jump_pressed:        bool,
	jump_held:           bool,
	reset_pressed:       bool,
	reset_scene_pressed: bool,
	debug_view_pressed:  bool,
	debug_mode_pressed:  bool,
	taa_pressed:         bool,
	perf_pressed:        bool,
	menu_toggle_pressed: bool,
	menu_up_pressed:     bool,
	menu_down_pressed:   bool,
	menu_left_pressed:   bool,
	menu_right_pressed:  bool,
	menu_confirm_pressed: bool,
	add_pressed:         bool,
	delete_pressed:      bool,
	sun_pressed:         bool,
	primary_pressed:     bool,
	primary_released:    bool,
	fly_up:              bool,
	fly_down:            bool,
	captured:            bool,
}


init :: proc(title: cstring, width, height: i32, fullscreen := false) -> (window: Window, err: Error) {
	if !sdl3.Init({.VIDEO}) {
		log.errorf("platform: SDL_Init failed: %v", sdl3.GetError())
		return {}, .SDL_Init
	}

	flags := sdl3.WindowFlags{.VULKAN, .RESIZABLE}
	if fullscreen {
		flags |= {.FULLSCREEN}
	}
	window.handle = sdl3.CreateWindow(title, width, height, flags)
	if window.handle == nil {
		message := string(sdl3.GetError())
		log.errorf("platform: SDL_CreateWindow failed: %s", message)
		if strings.contains(message, "VK_KHR_surface") {
			log.error("platform: no working Vulkan driver; check the installed ICD and VK_ICD_FILENAMES")
		}
		sdl3.Quit()
		return {}, .Create_Window
	}
	window.capture_on_click = true

	return window, .None
}

deinit :: proc(window: ^Window) {
	if window.handle != nil {
		sdl3.DestroyWindow(window.handle)
		window.handle = nil
	}
	sdl3.Quit()
}

vulkan_loader_proc :: proc() -> rawptr {
	return rawptr(sdl3.Vulkan_GetVkGetInstanceProcAddr())
}

// The slice points into SDL storage and stays valid for the window's lifetime.
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

wait_events :: proc(window: ^Window, timeout_ms: i32) -> (events: Events) {
	event: sdl3.Event
	if !sdl3.WaitEventTimeout(&event, timeout_ms) {
		return poll_events(window)
	}
	return drain_events(window, &event)
}

drain_events :: proc(window: ^Window, first: ^sdl3.Event) -> (events: Events) {
	events.captured = sdl3.GetWindowRelativeMouseMode(window.handle)
	mouse_x, mouse_y: f32
	buttons := sdl3.GetMouseState(&mouse_x, &mouse_y)
	events.pointer = {mouse_x, mouse_y}
	events.pointer_down = sdl3.MouseButtonFlag.LEFT in buttons
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
	events.sprint_held = keys[int(sdl3.Scancode.LSHIFT)]
	events.crouch_held = keys[int(sdl3.Scancode.C)]
	events.prone_held = keys[int(sdl3.Scancode.Z)]
	events.jump_held = keys[int(sdl3.Scancode.SPACE)]
	if keys[int(sdl3.Scancode.SPACE)] {
		events.fly_up = true
	}
	if keys[int(sdl3.Scancode.LCTRL)] || keys[int(sdl3.Scancode.RCTRL)] {
		events.fly_down = true
	}
}




apply_event :: proc(events: ^Events, event: ^sdl3.Event, window: ^Window) {
	#partial switch event.type {
	case .QUIT, .WINDOW_CLOSE_REQUESTED:
		events.quit = true
	case .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED:
		events.resized = true
	case .MOUSE_BUTTON_DOWN:
		if event.button.button == sdl3.BUTTON_LEFT {
			events.pointer_down = true
			events.pointer_pressed = true
			if events.captured {
				events.primary_pressed = true
			} else if window.capture_on_click {
				events.captured = set_cursor_capture(window, true)
			}
		}
	case .MOUSE_BUTTON_UP:
		if event.button.button == sdl3.BUTTON_LEFT {
			events.pointer_down = false
			events.pointer_released = true
			events.primary_released = true
		}
	case .MOUSE_WHEEL:
		if events.captured {
			events.wheel_delta += event.wheel.y
		}
	case .KEY_DOWN:
		if event.key.repeat {
			return
		}
		#partial switch event.key.scancode {
		case .ESCAPE:
			events.menu_toggle_pressed = true
		case .UP:
			events.menu_up_pressed = true
		case .DOWN:
			events.menu_down_pressed = true
		case .LEFT:
			events.menu_left_pressed = true
		case .RIGHT:
			events.menu_right_pressed = true
		case .RETURN, .KP_ENTER:
			events.menu_confirm_pressed = true
		case .SPACE:
			events.jump_pressed = true
		case .LSHIFT:
			events.sprint_pressed = true
		case .C:
			events.crouch_pressed = true
		case .Z:
			events.prone_pressed = true
		case .R:
			if .LSHIFT in event.key.mod || .RSHIFT in event.key.mod {
				events.reset_scene_pressed = true
			} else {
				events.reset_pressed = true
			}
		case .F1:
			events.debug_view_pressed = true
		case .F2:
			events.debug_mode_pressed = true
		case .F3:
			events.taa_pressed = true
		case .F4:
			events.perf_pressed = true
		case .E:
			events.add_pressed = true
		case .DELETE, .X:
			events.delete_pressed = true
		case .L:
			events.sun_pressed = true
		}
	case .MOUSE_MOTION:
		events.pointer = {event.motion.x, event.motion.y}
		if events.captured {
			events.look_delta.x += event.motion.xrel
			events.look_delta.y += event.motion.yrel
		}
	}
}
