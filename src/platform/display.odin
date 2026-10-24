#+vet explicit-allocators
package platform

import "core:c"
import "core:fmt"
import "core:log"
import "core:strings"

import "src:display"
import "vendor:sdl3"

// The SDL display IDs live here, so the game menu only needs the snapshot.
Displays :: struct {
	list: display.List,
	ids:  [display.MAX_DISPLAYS]sdl3.DisplayID,
}

query_displays :: proc() -> Displays {
	displays: Displays
	count: i32
	ids := sdl3.GetDisplays(&count)
	if ids == nil || count <= 0 {
		log.errorf("platform: SDL_GetDisplays failed: %v", sdl3.GetError())
		return displays
	}
	defer sdl3.free(rawptr(ids))
	primary := sdl3.GetPrimaryDisplay()
	for id in ids[:int(count)] {
		if displays.list.count >= display.MAX_DISPLAYS {
			break
		}
		if id == primary {
			append_display(&displays, id)
		}
	}
	for id in ids[:int(count)] {
		if displays.list.count >= display.MAX_DISPLAYS {
			break
		}
		if id != primary {
			append_display(&displays, id)
		}
	}
	return displays
}

display_index_for_window :: proc(window: ^Window, displays: ^Displays) -> int {
	if window == nil || window.handle == nil || displays == nil {
		return -1
	}
	id := sdl3.GetDisplayForWindow(window.handle)
	for index in 0 ..< displays.list.count {
		if displays.ids[index] == id {
			return index
		}
	}
	return -1
}

apply_window_state :: proc(
	window: ^Window,
	displays: ^Displays,
	settings: display.Window_Settings,
) -> bool {
	if window == nil || window.handle == nil || displays == nil {
		return false
	}
	index := display.clamp_index(&displays.list, settings.display)
	id := displays.ids[index]
	if id == 0 {
		log.error("platform: cannot apply the window settings without a display")
		return false
	}

	width := max(settings.resolution.width, 320)
	height := max(settings.resolution.height, 240)
	centered_x := sdl3.WINDOWPOS_CENTERED_DISPLAY(c.int(id))
	centered_y := sdl3.WINDOWPOS_CENTERED_DISPLAY(c.int(id))
	on_wayland := false
	if driver := sdl3.GetCurrentVideoDriver(); driver != nil {
		on_wayland = string(driver) == "wayland"
	}

	switch settings.mode {
	case .Borderless:
		_ = sdl3.SetWindowBordered(window.handle, false)
		// SDL resolves the fullscreen output from the pending position. Set it
		// before entering fullscreen; when already fullscreen it moves the window.
		_ = sdl3.SetWindowPosition(window.handle, centered_x, centered_y)
		if !sdl3.SetWindowFullscreen(window.handle, true) {
			log.errorf("platform: SDL_SetWindowFullscreen failed: %v", sdl3.GetError())
			return false
		}
	case .Windowed:
		was_fullscreen := .FULLSCREEN in sdl3.GetWindowFlags(window.handle)
		_ = sdl3.SetWindowFullscreen(window.handle, false)
		if .MAXIMIZED in sdl3.GetWindowFlags(window.handle) {
			_ = sdl3.RestoreWindow(window.handle)
		}
		_ = sdl3.SetWindowBordered(window.handle, true)
		// Equal size limits request a fixed size; tiling compositors that honor
		// the hint float the window. Open the maximum first so the new minimum
		// is valid.
		_ = sdl3.SetWindowMaximumSize(window.handle, 0, 0)
		if !sdl3.SetWindowMinimumSize(window.handle, c.int(width), c.int(height)) {
			log.errorf("platform: SDL_SetWindowMinimumSize failed: %v", sdl3.GetError())
			return false
		}
		if !sdl3.SetWindowMaximumSize(window.handle, c.int(width), c.int(height)) {
			log.errorf("platform: SDL_SetWindowMaximumSize failed: %v", sdl3.GetError())
			return false
		}
		if !sdl3.SetWindowSize(window.handle, c.int(width), c.int(height)) {
			log.errorf("platform: SDL_SetWindowSize failed: %v", sdl3.GetError())
			return false
		}
		// Wayland lets only the compositor place a normal window. The position
		// still selects the output for the next Borderless fullscreen.
		_ = sdl3.SetWindowPosition(window.handle, centered_x, centered_y)
		if was_fullscreen && on_wayland {
			// A tiling compositor can keep the old tiled slot. A fresh map lets
			// it apply the fixed size and float the window.
			_ = sdl3.HideWindow(window.handle)
			_ = sdl3.ShowWindow(window.handle)
		}
	}
	if !sdl3.SyncWindow(window.handle) {
		log.errorf("platform: SDL_SyncWindow failed: %v", sdl3.GetError())
		return false
	}
	return true
}

@(private)
append_display :: proc(displays: ^Displays, id: sdl3.DisplayID) {
	index := displays.list.count
	fill_display(&displays.list.items[index], id, index)
	displays.ids[index] = id
	displays.list.count += 1
}

@(private)
fill_display :: proc(info: ^display.Info, id: sdl3.DisplayID, index: int) {
	full := sdl3.GetDisplayName(id)
	if full != nil {
		set_short_name(info, string(full), index)
	} else {
		set_short_name(info, "", index)
	}

	desktop := sdl3.GetDesktopDisplayMode(id)
	if desktop != nil {
		display.set_desktop(info, {desktop.w, desktop.h})
	}

	mode_count: i32
	modes := sdl3.GetFullscreenDisplayModes(id, &mode_count)
	if modes != nil {
		defer sdl3.free(rawptr(modes))
		for mode_index in 0 ..< mode_count {
			mode := modes[mode_index]
			// Smaller windows clip the settings menu. The desktop mode is added
			// separately, even when it is smaller.
			if !display.keep_windowed_mode({mode.w, mode.h}) {
				continue
			}
			display.add_mode(info, {mode.w, mode.h})
		}
	}
	display.sort_modes(info)
	log.infof(
		"platform: display %d %s has %d modes",
		index + 1,
		display.name(info),
		info.mode_count,
	)
}

@(private)
set_short_name :: proc(info: ^display.Info, full: string, index: int) {
	name := full
	if open := strings.last_index(full, " ("); open >= 0 && strings.has_suffix(full, ")") {
		name = full[open + 2 : len(full) - 1]
	}
	if name == "" {
		buffer: [display.NAME_MAX]u8
		name = fmt.bprintf(buffer[:], "Display %d", index + 1)
	}
	display.set_name(info, name)
}
