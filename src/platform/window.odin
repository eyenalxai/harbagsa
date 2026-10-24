#+vet explicit-allocators
package platform

import "core:c"
import "core:log"
import "vendor:sdl3"

sync_window :: proc(window: ^Window) {
	sdl3.SyncWindow(window.handle)
}

window_size :: proc(window: ^Window) -> (width, height: f32) {
	w, h: c.int
	if !sdl3.GetWindowSize(window.handle, &w, &h) {
		return 0, 0
	}
	return f32(w), f32(h)
}

is_minimized :: proc(window: ^Window) -> bool {
	return .MINIMIZED in sdl3.GetWindowFlags(window.handle)
}

set_cursor_capture :: proc(window: ^Window, enabled: bool) -> bool {
	if !sdl3.SetWindowRelativeMouseMode(window.handle, enabled) {
		log.errorf("platform: SDL_SetWindowRelativeMouseMode failed: %v", sdl3.GetError())
	}
	return sdl3.GetWindowRelativeMouseMode(window.handle)
}

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

set_click_capture :: proc(window: ^Window, allowed: bool) {
	window.capture_on_click = allowed
}
