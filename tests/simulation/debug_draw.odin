#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"
import game "src:game"

@(test)
debug_line_collectors_fill_lines :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	lines: game.Debug_Lines
	game.collect_world_lines(&sim, &lines)
	testing.expect(t, lines.count > 0, "world debug lines are empty")

	dm := game.debug_mode_create()
	game.debug_mode_toggle(&dm, &sim)
	lines.count = 0
	game.collect_editor_lines(&dm, &sim, &lines)
	testing.expect(t, lines.count > 0, "editor debug lines are empty")
}
