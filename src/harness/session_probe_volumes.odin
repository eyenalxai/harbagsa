#+vet explicit-allocators
package harness

import "src:frame"

// A scene block replaces the production probe layout for the rest of the run.
// The composed list puts the extras after the room volume, so an interior test
// room wins the sampler before the open-arena strips.
session_set_probe_volumes :: proc(
	session: ^Session,
	extras: []frame.Scene_Probe_Volume,
) -> string {
	session_clear_probe_volumes(session)
	if len(extras) == 0 {
		return ""
	}
	specs := frame.scene_probe_volumes_clone(extras, session.allocator)
	volumes, compose_error := frame.probe_volumes_compose(specs, session.allocator)
	if compose_error != "" {
		frame.scene_probe_volumes_destroy(specs, session.allocator)
		return format_error("%s", compose_error)
	}
	session.scene_probe_volumes = specs
	session.probe_volumes = volumes
	session.has_probe_volumes = true
	return ""
}

session_clear_probe_volumes :: proc(session: ^Session) {
	if session.probe_volumes != nil {
		delete(session.probe_volumes, session.allocator)
		session.probe_volumes = nil
	}
	frame.scene_probe_volumes_destroy(session.scene_probe_volumes, session.allocator)
	session.scene_probe_volumes = nil
	session.has_probe_volumes = false
}
