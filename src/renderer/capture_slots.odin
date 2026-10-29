#+vet explicit-allocators
#+vet !unused-procedures // the harness reads the slots; the game binary does not
package renderer

// A capture plan names the images one frame must copy out. Beauty reads the
// color target; `views` holds term views only, and each reads its own image.
Frame_Capture :: struct {
	targets: Capture_Targets,
	views:   Capture_Views,
}

capture_has_term_views :: proc(capture: Frame_Capture) -> bool {
	for _ in capture.views {
		return true
	}
	return false
}

// Targets come first in enum order, then the term views. The harness and the
// recorder read the same order, so one index names one readback slot.
capture_slot_count :: proc(capture: Frame_Capture) -> int {
	count := 0
	for _ in capture.targets {
		count += 1
	}
	for _ in capture.views {
		count += 1
	}
	return count
}

capture_target_slot :: proc(capture: Frame_Capture, target: Capture_Target) -> int {
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

capture_view_slot :: proc(capture: Frame_Capture, view: Capture_View) -> int {
	if view not_in capture.views {
		return -1
	}
	slot := 0
	for _ in capture.targets {
		slot += 1
	}
	for candidate in Capture_View {
		if candidate == .Beauty {
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
