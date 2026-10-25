#+vet explicit-allocators
package harness

import "core:log"

Run_Backend :: struct {
	width:     u32,
	height:    u32,
	present:   bool,
	frames_dir: string,
	backend:   ^Backend,
	session:   ^Session,
}

run_backend_ensure :: proc(ctx: rawptr) -> string {
	run := cast(^Run_Backend)ctx
	if run.backend.ready {
		return ""
	}
	created, create_error := backend_create(
		run.width,
		run.height,
		run.present,
		run.frames_dir,
		context.allocator,
	)
	if create_error != "" {
		log.errorf("harness: %s", create_error)
		return create_error
	}
	run.backend^ = created
	session_set_backend(run.session, run.backend, run.present)
	return ""
}
