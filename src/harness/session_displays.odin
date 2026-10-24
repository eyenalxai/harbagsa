#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"

import "src:display"

Display_State :: struct {
	name:    string   `json:"name"`,
	desktop: string   `json:"desktop"`,
	modes:   []string `json:"modes"`,
}

Displays_State :: struct {
	count:    int             `json:"count"`,
	displays: []Display_State `json:"displays"`,
}

session_displays :: proc(session: ^Session, command: Displays_Command) {
	if command.clear {
		session.hud.menu.displays = display.fallback_list()
		return
	}
	list: display.List
	for entry in command.set {
		if list.count >= display.MAX_DISPLAYS {
			break
		}
		info := &list.items[list.count]
		display.set_name(info, entry.name)
		if entry.has_desktop {
			display.set_desktop(info, {entry.desktop.width, entry.desktop.height})
		}
		for mode in entry.modes {
			display.add_mode(info, {mode.width, mode.height})
		}
		display.sort_modes(info)
		list.count += 1
	}
	session.hud.menu.displays = list
}

displays_state_build :: proc(list: ^display.List, allocator: mem.Allocator) -> Displays_State {
	state := Displays_State{count = list.count}
	state.displays = make([]Display_State, list.count, allocator)
	for index in 0 ..< list.count {
		info := &list.items[index]
		state.displays[index] = {
			name    = fmt.aprintf("%s", display.name(info), allocator = allocator),
			desktop = mode_state(info.desktop, allocator),
			modes   = make([]string, info.mode_count, allocator),
		}
		for mode, mode_index in info.modes[:info.mode_count] {
			state.displays[index].modes[mode_index] = mode_state(mode, allocator)
		}
	}
	return state
}

displays_state_destroy :: proc(state: ^Displays_State, allocator: mem.Allocator) {
	for &entry in state.displays {
		delete(entry.name, allocator)
		for mode in entry.modes {
			delete(mode, allocator)
		}
		delete(entry.modes, allocator)
	}
	if state.displays != nil {
		delete(state.displays, allocator)
	}
	state^ = {}
}

@(private)
mode_state :: proc(mode: display.Mode, allocator: mem.Allocator) -> string {
	return fmt.aprintf("%dx%d", mode.width, mode.height, allocator = allocator)
}
