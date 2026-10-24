#+vet explicit-allocators
package harness

import b3 "libs:box3d"

import "src:game"

session_crates :: proc(session: ^Session, command: Crates_Command) -> string {
	switch command.action {
	case .Reset:
		game.simulation_reset_crates(&session.sim)
	case .Clear:
		for game.simulation_crate_count(&session.sim) > 0 {
			if !game.simulation_remove_crate(&session.sim, 0) {
				return format_error("could not clear the crates")
			}
		}
	case .Add:
		return session_crates_add(session, command.add)
	case .Remove:
		if !game.simulation_remove_crate(&session.sim, command.remove_index) {
			return format_error("crate index %d is out of range", command.remove_index)
		}
	}
	return ""
}

@(private)
session_crates_add :: proc(session: ^Session, add: Crates_Add) -> string {
	start := game.simulation_crate_count(&session.sim)
	if add.count > game.MAX_CRATES - start {
		return format_error(
			"adding %d crates would exceed the %d crate limit",
			add.count,
			game.MAX_CRATES,
		)
	}
	for index in 0 ..< add.count {
		column := index % add.columns
		row := index / add.columns
		position := b3.Vec3 {
			add.origin.x + f32(column) * add.spacing.x,
			add.origin.y,
			add.origin.z + f32(row) * add.spacing.z,
		}
		if game.simulation_add_default_crate(&session.sim, position) < 0 {
			for game.simulation_crate_count(&session.sim) > start {
				_ = game.simulation_remove_crate(
					&session.sim,
					game.simulation_crate_count(&session.sim) - 1,
				)
			}
			return format_error("crate %d could not be created", index)
		}
	}
	return ""
}
