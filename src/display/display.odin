#+vet explicit-allocators
#+vet !unused-procedures // the agent harness and tests build the fallback list
package display

MAX_DISPLAYS :: 8
MAX_MODES :: 64
NAME_MAX :: 32

// The settings menu owns a snapshot of this list, so the text stays stable while
// the menu is open.
Mode :: struct {
	width:  i32,
	height: i32,
}

Window_Mode :: enum {
	Borderless,
	Windowed,
}

Window_Settings :: struct {
	mode:       Window_Mode,
	display:    int,
	resolution: Mode,
}

Info :: struct {
	name:       [NAME_MAX]u8,
	name_count: int,
	desktop:    Mode,
	modes:      [MAX_MODES]Mode,
	mode_count: int,
}

List :: struct {
	items: [MAX_DISPLAYS]Info,
	count: int,
}

name :: proc(info: ^Info) -> string {
	return string(info.name[:info.name_count])
}

set_name :: proc(info: ^Info, text: string) {
	count := min(len(text), NAME_MAX)
	copy(info.name[:], text[:count])
	info.name_count = count
}

set_desktop :: proc(info: ^Info, mode: Mode) {
	info.desktop = mode
	add_mode(info, mode)
}

add_mode :: proc(info: ^Info, mode: Mode) {
	if mode.width <= 0 || mode.height <= 0 {
		return
	}
	for index in 0 ..< info.mode_count {
		existing := info.modes[index]
		if existing.width == mode.width && existing.height == mode.height {
			return
		}
	}
	if info.mode_count >= MAX_MODES {
		return
	}
	info.modes[info.mode_count] = mode
	info.mode_count += 1
}

sort_modes :: proc(info: ^Info) {
	for index in 1 ..< info.mode_count {
		mode := info.modes[index]
		cursor := index
		for cursor > 0 && mode_before(mode, info.modes[cursor - 1]) {
			info.modes[cursor] = info.modes[cursor - 1]
			cursor -= 1
		}
		info.modes[cursor] = mode
	}
}

clamp_index :: proc(list: ^List, index: int) -> int {
	if list.count <= 0 || index < 0 || index >= list.count {
		return 0
	}
	return index
}

info_at :: proc(list: ^List, index: int) -> ^Info {
	return &list.items[clamp_index(list, index)]
}

find_mode :: proc(info: ^Info, mode: Mode) -> int {
	for index in 0 ..< info.mode_count {
		if info.modes[index] == mode {
			return index
		}
	}
	return -1
}

snap_mode :: proc(info: ^Info, mode: Mode) -> Mode {
	if info.mode_count == 0 {
		return mode
	}
	if find_mode(info, mode) >= 0 {
		return mode
	}
	best := info.modes[0]
	best_distance := mode_distance(best, mode)
	for index in 1 ..< info.mode_count {
		candidate := info.modes[index]
		distance := mode_distance(candidate, mode)
		if distance < best_distance {
			best = candidate
			best_distance = distance
		}
	}
	return best
}

cycle_mode :: proc(info: ^Info, mode: Mode, direction: int) -> Mode {
	if info.mode_count == 0 {
		return mode
	}
	index := find_mode(info, mode)
	if index < 0 {
		index = 0
	} else {
		index = (index + direction + info.mode_count) % info.mode_count
	}
	return info.modes[index]
}

fallback_list :: proc() -> List {
	list: List
	list.count = 2
	add_display(
		&list.items[0],
		"Display 1",
		{1920, 1080},
		[]Mode{{1920, 1080}, {1600, 900}, {1280, 720}},
	)
	add_display(
		&list.items[1],
		"Display 2",
		{2560, 1440},
		[]Mode{{2560, 1440}, {1920, 1080}, {1280, 720}},
	)
	return list
}

@(private)
add_display :: proc(info: ^Info, display_name: string, desktop: Mode, modes: []Mode) {
	set_name(info, display_name)
	set_desktop(info, desktop)
	for mode in modes {
		add_mode(info, mode)
	}
	sort_modes(info)
}

@(private)
mode_before :: proc(a, b: Mode) -> bool {
	area_a := i64(a.width) * i64(a.height)
	area_b := i64(b.width) * i64(b.height)
	if area_a != area_b {
		return area_a > area_b
	}
	if a.width != b.width {
		return a.width > b.width
	}
	return a.height > b.height
}

@(private)
mode_distance :: proc(a, b: Mode) -> i64 {
	distance := i64(a.width) * i64(a.height) - i64(b.width) * i64(b.height)
	if distance < 0 {
		return -distance
	}
	return distance
}
