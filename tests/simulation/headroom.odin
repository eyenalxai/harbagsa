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
		name: string,
		feet: [3]f32,
		want: game.Stance,
	}
	// Each z sits under a slab that clears the expected stance but not the one
	// above it.
	ramps := [3]Ramp {
		{"20 degree", game.ARENA_RAMP_20_UNDER, .Crouching},
		{"40 degree", game.ARENA_RAMP_40_UNDER, .Crouching},
		{"50 degree", game.ARENA_RAMP_50_UNDER, .Prone},
	}
	for ramp in ramps {
		sim := create(t)
		testing.expectf(
			t,
			!game.has_headroom(&sim, ramp.feet, .Standing),
			"standing headroom reported under the %s ramp",
			ramp.name,
		)

		game.player_place(&sim.player, ramp.feet, 0.0, 0.0)
		game.commit_stance(&sim.player, .Prone)
		step(&sim, game.Input_Snapshot{prone_pressed = true}, 1)

		testing.expectf(
			t,
			sim.player.stance == ramp.want,
			"under the %s ramp: stance %v, want %v",
			ramp.name,
			sim.player.stance,
			ramp.want,
		)
		game.simulation_destroy(&sim)
	}
}

@(test)
headroom_keeps_the_standing_stance_on_a_ramp :: proc(t: ^testing.T) {
	Approach :: struct {
		name:     string,
		position: [3]f32,
	}
	approaches := [2]Approach {
		{"20 degree", game.ARENA_RAMP_20_APPROACH},
		{"40 degree", game.ARENA_RAMP_40_APPROACH},
	}
	for approach in approaches {
		sim := create(t)
		sim.player.position = approach.position
		sim.player.velocity = {}
		sim.player.yaw = 0
		for frame in 0 ..< 60 {
			step(&sim, game.Input_Snapshot{move_forward = 1.0}, 1)
			if sim.player.stance != .Standing {
				testing.expectf(
					t,
					false,
					"the %s ramp dropped the stance on frame %v at y=%v",
					approach.name,
					frame,
					sim.player.position.y,
				)
				break
			}
		}
		testing.expectf(
			t,
			sim.player.position.y > 0.5,
			"the %s ramp did not lift the player: y=%v",
			approach.name,
			sim.player.position.y,
		)
		game.simulation_destroy(&sim)
	}
}

// A side obstacle that only grazes the capsule must not block a taller stance,
// or the player cannot stand beside a wall, a crate, or a step.
@(test)
headroom_allows_a_side_obstacle :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	wall := b3.Vec3 {
		game.ARENA_HALF_SIZE - game.PLAYER_RADIUS,
		game.GROUND_OFFSET,
		0.0,
	}
	testing.expect(t, game.has_headroom(&sim, wall, .Standing), "a wall blocked standing")

	crate_center := game.INITIAL_CRATE_POSITIONS[0]
	crate := b3.Vec3 {
		crate_center[0] + 0.5 + game.PLAYER_RADIUS,
		game.GROUND_OFFSET,
		crate_center[2],
	}
	testing.expect(t, game.has_headroom(&sim, crate, .Standing), "a crate blocked standing")

	step_face := b3.Vec3 {
		game.ARENA_STEP_035_X + game.ARENA_STEP_HALF + game.PLAYER_RADIUS,
		game.GROUND_OFFSET,
		game.ARENA_STEP_035_Z,
	}
	testing.expect(t, game.has_headroom(&sim, step_face, .Standing), "a step blocked standing")
}
