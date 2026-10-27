#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import b3 "libs:box3d"
import game "src:game"

@(test)
arena_ceiling_covers_the_outer_shell :: proc(t: ^testing.T) {
	boxes := game.arena_static_boxes()
	testing.expect_value(t, len(boxes), game.ARENA_STATIC_BOX_COUNT)

	ceiling := boxes[game.ARENA_BASE_BOX_COUNT - 1]
	testing.expect_value(
		t,
		ceiling.center.y,
		game.ARENA_WALL_HEIGHT + game.ARENA_CEILING_THICKNESS * 0.5,
	)
	testing.expect_value(
		t,
		ceiling.half_extents.x,
		game.ARENA_HALF_SIZE + game.ARENA_WALL_THICKNESS,
	)
	testing.expect_value(t, ceiling.half_extents.z, ceiling.half_extents.x)
	testing.expect_value(t, ceiling.half_extents.y, game.ARENA_CEILING_THICKNESS * 0.5)
	testing.expect_value(t, ceiling.color, game.CEILING_COLOR)
}

@(test)
arena_ceiling_stops_upward_motion :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	game.player_place(&sim.player, b3.Vec3{0, 2.0, 0}, 0, 0)
	sim.player.velocity.y = 8.0

	peak := sim.player.position.y
	for _ in 0 ..< 30 {
		game.simulation_step(&sim, {}, DT)
		peak = max(peak, sim.player.position.y)
	}

	max_feet: f32 = game.ARENA_WALL_HEIGHT - game.PLAYER_STANDING_HEIGHT
	testing.expectf(t, peak > max_feet - 0.1, "the player never reached the ceiling: peak=%v", peak)
	testing.expectf(t, peak <= max_feet + 0.02, "the player crossed the ceiling: peak=%v", peak)
}
