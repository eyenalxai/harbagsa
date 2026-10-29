#+vet explicit-allocators
package renderer

// A capture plan names the images one frame must copy out. Beauty reads the
// color target; every term view reads its own view image.
Frame_Capture :: struct {
	targets: Capture_Targets,
	views:   Capture_Views,
}

// Targets come first in enum order, then the term views. The harness and the
// recorder read the same order, so one index names one readback slot.
capture_slot_count :: proc(capture: Frame_Capture) -> int {	count := 0
	for _ in capture.targets {
		count += 1
	}
	for view in capture.views {
		if capture_view_is_term(view) {
			count += 1
		}
	}
	return count
}

capture_has_term_views :: proc(capture: Frame_Capture) -> bool {
	for view in capture.views {
		if capture_view_is_term(view) {
			return true
		}
	}
	return false
}

capture_slot :: proc(capture: Frame_Capture, target: Capture_Target, view: Capture_View) -> int {
	if capture_view_is_term(view) {
		if view not_in capture.views {
			return -1
		}
		slot := 0
		for _ in capture.targets {
			slot += 1
		}
		for candidate in Capture_View {
			if !capture_view_is_term(candidate) {
				continue
			}
			if candidate == view {
				return slot
			}
			if candidate in capture.views {
				slot += 1
			}
		}
		return -1
	}
	if target not_in capture.targets {
		return -1
	}
	slot := 0
	for candidate in Capture_Target {
		if candidate == target {
			return slot
		}
		if candidate in capture.targets {
			slot += 1
		}
	}
	return -1
}
