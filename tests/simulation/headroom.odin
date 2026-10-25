#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"
import b3 "libs:box3d"
import game "src:game"

@(test)
headroom_drops_the_player_under_each_tunnel :: proc(t: ^testing.T) {
	Tunnel :: struct {
		position: [3]f32,
		stance:   game.Stance,
	}
	tunnels := [3]Tunnel {
		{game.ARENA_TUNNEL_135_POSITION, .Crouching},
		{game.ARENA_TUNNEL_122_POSITION, .Crouching},
		{game.ARENA_TUNNEL_090_POSITION, .Prone},
	}
	for tunnel in tunnels {
		sim := create(t)
		sim.player.position = tunnel.position
		sim.player.velocity = {}
		step(&sim, {}, 2)
		testing.expect_value(t, sim.player.stance, tunnel.stance)
		game.simulation_destroy(&sim)
	}
}

// A prone player under a ramp faces a sloped underside. Its AABB starts below
// the feet, so an AABB test misses it and the player stands through the slab.
@(test)
headroom_refuses_a_taller_stance_under_a_ramp :: proc(t: ^testing.T) {
	Ramp :: struct {
		x:      f32,
		z:      f32,
		stance: game.Stance,
	}
	// The z values sit under a slab that clears the prone capsule but not the
	// next stance up.
	ramps := [3]Ramp {
		{game.ARENA_RAMP_20_X, -4.5, .Crouching},
		{game.ARENA_RAMP_40_X, -2.0, .Crouching},
		{game.ARENA_RAMP_50_X, -1.2, .Prone},
	}
	for ramp in ramps {
		sim := create(t)
		feet := b3.Vec3{ramp.x, game.GROUND_OFFSET, ramp.z}
		testing.expectf(
			t,
			!game.has_headroom(&sim, feet, .Standing),
			"standing headroom reported under the ramp at x=%v z=%v",
			ramp.x,
			ramp.z,
		)

		game.player_place(&sim.player, feet, 0.0, 0.0)
		game.commit_stance(&sim.player, .Prone)
		step(&sim, {}, 1)
		game.simulation_step(&sim, game.Input_Snapshot{prone_pressed = true}, game.SIMULATION_STEP)

		testing.expectf(
			t,
			sim.player.stance == ramp.stance,
			"under the ramp at x=%v z=%v: stance %v, want %v",
			ramp.x,
			ramp.z,
			sim.player.stance,
			ramp.stance,
		)
		game.simulation_destroy(&sim)
	}
}

@(test)
headroom_keeps_the_standing_stance_on_a_ramp :: proc(t: ^testing.T) {
	approaches := [2][3]f32 {
		game.ARENA_RAMP_20_APPROACH,
		game.ARENA_RAMP_40_APPROACH,
	}
	for approach in approaches {
		sim := create(t)
		sim.player.position = approach
		sim.player.velocity = {}
		sim.player.yaw = 0
		for frame in 0 ..< 120 {
			step(&sim, game.Input_Snapshot{move_forward = 1.0}, 1)
			if sim.player.stance != .Standing {
				testing.expectf(
					t,
					false,
					"the ramp dropped the stance on frame %v at y=%v",
					frame,
					sim.player.position.y,
				)
				break
			}
		}
		game.simulation_destroy(&sim)
	}
}

// A floor-level side obstacle only touches the lower body. It must not block a
// taller stance, or the player cannot stand beside a wall or a step.
@(test)
headroom_allows_a_side_obstacle_at_the_feet :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	wall := b3.Vec3 {
		game.ARENA_HALF_SIZE - game.PLAYER_RADIUS,
		game.GROUND_OFFSET,
		0.0,
	}
	testing.expect(t, game.has_headroom(&sim, wall, .Standing), "a wall blocked standing")

	step_face := b3.Vec3 {
		game.ARENA_STEP_035_X + game.ARENA_STEP_HALF + game.PLAYER_RADIUS,
		game.GROUND_OFFSET,
		game.ARENA_STEP_035_Z,
	}
	testing.expect(t, game.has_headroom(&sim, step_face, .Standing), "a step blocked standing")
}
