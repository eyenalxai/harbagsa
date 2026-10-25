#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"
import game "src:game"

@(test)
world_debug_lines_fill :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	lines: game.Debug_Lines
	game.collect_world_lines(&sim, &lines)
	testing.expect(t, lines.count > 0, "world debug lines are empty")
}

@(test)
editor_debug_lines_are_empty_until_a_tool_is_armed :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)
	dm := game.debug_mode_create(context.allocator)
	defer game.debug_mode_destroy(&dm)

	game.debug_mode_toggle(&dm, &sim)
	lines: game.Debug_Lines
	game.collect_editor_lines(&dm, &sim, &lines)
	testing.expect_value(t, lines.count, 0)
}

@(test)
sun_gizmo_draws_only_in_sun_placement :: proc(t: ^testing.T) {
	dm := game.debug_mode_create(context.allocator)
	defer game.debug_mode_destroy(&dm)
	lines: game.Debug_Lines
	game.collect_sun_editor_lines(&dm, &lines)
	testing.expect_value(t, lines.count, 0)

	dm.sun.active = true
	lines.count = 0
	game.collect_sun_editor_lines(&dm, &lines)
	testing.expect(t, lines.count > 40, "the sun gizmo has no ring or dashed line")
	testing.expect_value(t, lines.lines[0].color, game.SUN_GIZMO_COLOR)
}
