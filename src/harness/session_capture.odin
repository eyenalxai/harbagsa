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
	frame := command.has_frame ? command.frame : session.frame
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
		spec  = command.spec,
		alpha = alpha,
	}
	request.name = name
	return session_queue_capture_group(session, frame, command.has_frame, []Capture_Request{request})
}

session_queue_captures :: proc(
	session: ^Session,
	command: Captures_Command,
) -> (
	immediate: bool,
	error: string,
) {
	frame := command.has_frame ? command.frame : session.frame
	alpha := command.has_alpha ? command.alpha : session.alpha
	requests := make([]Capture_Request, len(command.outputs), context.temp_allocator)
	for output, index in command.outputs {
		requests[index] = {
			spec  = output.spec,
			alpha = alpha,
		}
	}
	return session_queue_capture_group(session, frame, command.has_frame, requests)
}

@(private)
session_queue_capture_group :: proc(
	session: ^Session,
	frame: int,
	has_frame: bool,
	requests: []Capture_Request,
) -> (
	immediate: bool,
	error: string,
) {
	if !session.render.enabled {
		log.warn("harness: capture skipped because rendering is disabled")
		return true, ""
	}
	if len(requests) == 0 {
		return true, format_error("%s", "a capture group needs at least one output")
	}
	if has_frame && frame < session.frame {
		return false, fmt.aprintf(
			"capture frame %d is in the past (current frame %d)",
			frame,
			session.frame,
			allocator = context.allocator,
		)
	}
	for request, index in requests {
		if request.name == "" {
			return false, format_error("%s", "a capture needs a name")
		}
		if capture_name_in_use(session, request.name) {
			return false, fmt.aprintf(
				"capture name %q is already used in this run",
				request.name,
				allocator = context.allocator,
			)
		}
		for previous in requests[:index] {
			if previous.name == request.name {
				return false, fmt.aprintf(
					"capture name %q is used twice in one group",
					request.name,
					allocator = context.allocator,
				)
			}
		}
	}
	if frame == session.frame {
		return true, session_draw_group(session, requests)
	}
	pending: Pending_Capture
	pending.frame = frame
	pending.requests = make([]Capture_Request, len(requests), session.allocator)
	for request, index in requests {
		pending.requests[index] = request
		pending.requests[index].name = strings.clone(request.name, session.allocator)
		pending.requests[index].note = strings.clone(request.note, session.allocator)
	}
	append(&session.capture.pending, pending)
	return false, ""
}

@(private)
capture_name_in_use :: proc(session: ^Session, name: string) -> bool {
	for capture in session.capture.captures {
		if capture.name == name {
			return true
		}
	}
	for pending in session.capture.pending {
		for request in pending.requests {
			if request.name == name {
				return true
			}
		}
	}
	return false
}

@(private)
ordered_remove :: proc(array: ^[dynamic]Pending_Capture, index: int) {
	for next in index ..< len(array^) - 1 {
		array[next] = array[next + 1]
	}
	resize(array, len(array^) - 1)
}
