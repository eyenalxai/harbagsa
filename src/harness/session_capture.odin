#+vet explicit-allocators
package harness

import "core:fmt"
import "core:log"
import "core:strings"

session_queue_capture :: proc(
	session: ^Session,
	command: Capture_Command,
) -> (
	immediate: bool,
	error: string,
) {
	if !session.render_enabled {
		log.warn("harness: capture skipped because rendering is disabled")
		return true, ""
	}
	frame := command.has_frame ? command.frame : session.frame
	if frame < session.frame {
		return false, fmt.aprintf(
			"capture frame %d is in the past (current frame %d)",
			frame,
			session.frame,
			allocator = context.allocator,
		)
	}
	name := command.name
	owned_name := false
	if name == "" {
		name = capture_name(frame, session.allocator)
		owned_name = true
	}
	defer if owned_name {
		delete(name, session.allocator)
	}
	alpha := command.has_alpha ? command.alpha : session.alpha
	request := Capture_Request {
		name      = name,
		alpha     = alpha,
		target    = command.target,
		format    = command.format,
		enabled   = true,
		region    = command.region,
		profile   = command.profile,
		crop      = command.crop,
		histogram = command.histogram,
	}
	if frame == session.frame {
		return true, session_draw(session, request)
	}
	append(
		&session.pending,
		Pending_Capture {
			name      = strings.clone(name, session.allocator),
			frame     = frame,
			alpha     = alpha,
			target    = command.target,
			format    = command.format,
			region    = command.region,
			profile   = command.profile,
			crop      = command.crop,
			histogram = command.histogram,
		},
	)
	return false, ""
}

@(private)
ordered_remove :: proc(array: ^[dynamic]Pending_Capture, index: int) {
	for next in index ..< len(array^) - 1 {
		array[next] = array[next + 1]
	}
	resize(array, len(array^) - 1)
}
