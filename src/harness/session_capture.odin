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
	alpha := command.has_alpha ? command.alpha : session.alpha
	base_name := command.name
	owned_name := false
	if base_name == "" {
		base_name = capture_name(frame, session.allocator)
		owned_name = true
	}
	defer if owned_name {
		delete(base_name, session.allocator)
	}
	requests := make([dynamic]Capture_Request, 0, max(len(command.views), 1), context.temp_allocator)
	defer delete(requests)
	if request_error := append_capture_requests(&requests, command, alpha, base_name); request_error != "" {
		return false, request_error
	}
	return session_queue_capture_group(session, frame, command.has_frame, requests[:])
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
	requests := make([dynamic]Capture_Request, 0, len(command.outputs), context.temp_allocator)
	defer delete(requests)
	for output in command.outputs {
		base_name := output.name
		if base_name == "" {
			base_name = capture_name(frame, context.temp_allocator)
		}
		if request_error := append_capture_requests(&requests, output, alpha, base_name); request_error != "" {
			return false, request_error
		}
	}
	return session_queue_capture_group(session, frame, command.has_frame, requests[:])
}

// A command with `views` expands into one request per view. The base name is
// the command's own name, or the generated frame name; every combined name is
// checked again because a generated name only appears here.
@(private)
append_capture_requests :: proc(
	requests: ^[dynamic]Capture_Request,
	command: Capture_Command,
	alpha: f32,
	base_name: string,
) -> string {
	if len(command.views) == 0 {
		request := Capture_Request {
			spec  = command.spec,
			alpha = alpha,
		}
		request.name = base_name
		append(requests, request)
		return ""
	}
	for view in command.views {
		request := Capture_Request {
			spec  = command.spec,
			alpha = alpha,
		}
		request.view = view
		request.name = capture_view_request_name(base_name, view, context.temp_allocator)
		if !valid_capture_name(request.name) {
			return format_error("capture name %q does not pass the name rule", request.name)
		}
		append(requests, request)
	}
	return ""
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
