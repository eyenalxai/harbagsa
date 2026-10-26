#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:frame"
import "src:harness"

SEALED_SCENARIO :: "scenarios/ddgi-sealed.json"

@(test)
sealed_scenario_supplies_its_own_probe_volumes :: proc(t: ^testing.T) {
	scenario, load_error := harness.scenario_load(SEALED_SCENARIO, context.allocator)
	if load_error != "" {
		testing.expectf(t, false, "cannot load %s: %s", SEALED_SCENARIO, load_error)
		return
	}
	defer harness.scenario_destroy(&scenario, context.allocator)

	extras: []frame.Scene_Probe_Volume
	for command in scenario.commands {
		if command.kind == .Scene && command.scene.has_probe_volumes {
			extras = command.scene.scene.probe_volumes
		}
	}
	testing.expect_value(t, len(extras), 2)
	if len(extras) == 2 {
		testing.expect_value(t, extras[0].name, "room-a")
		testing.expect_value(t, extras[0].min, [3]f32{-13.8, 0, -9.8})
		testing.expect_value(t, extras[1].name, "room-b")
		testing.expect_value(t, extras[1].min, [3]f32{-9.8, 0, -9.8})
		testing.expect_value(t, extras[0].counts, [3]u32{4, 3, 4})
		testing.expect_value(t, extras[0].spacing, f32(1.0))
	}

	volumes, compose_error := frame.probe_volumes_compose(extras, context.allocator)
	defer delete(volumes, context.allocator)
	if compose_error != "" {
		testing.expectf(t, false, "cannot compose the probe volumes: %s", compose_error)
		return
	}
	testing.expect_value(t, len(volumes), 8)
	total := 0
	for volume in volumes {
		total += frame.probe_volume_probe_count(volume)
	}
	testing.expect_value(t, total, 2301)

	// The pair volumes sit after the room and before the arena strips, so a
	// room B surface samples room B's own probes.
	room_a := [3]f32{-12.0, 1.5, -8.0}
	room_b := [3]f32{-8.0, 1.5, -8.0}
	testing.expect_value(t, frame.probe_volume_owner(volumes, room_a), 1)
	testing.expect_value(t, frame.probe_volume_owner(volumes, room_b), 2)
}

@(test)
default_scene_has_no_test_room :: proc(t: ^testing.T) {
	total := 0
	for volume in frame.PROBE_VOLUMES {
		total += frame.probe_volume_probe_count(volume)
	}
	testing.expect_value(t, len(frame.PROBE_VOLUMES), 6)
	testing.expect_value(t, total, 2205)
}

@(test)
probe_volume_owner_matches_the_gather_edge :: proc(t: ^testing.T) {
	room := frame.PROBE_VOLUMES[0]
	high := frame.probe_volume_high(room)
	edge := high
	testing.expect(t, frame.probe_volume_owner(frame.PROBE_VOLUMES[:], edge) == 0)
	// 1 mm past the high bound is outside; the gather adds the same 1 mm.
	edge.x += frame.PROBE_VOLUME_EDGE_EPSILON + 0.001
	testing.expect(t, frame.probe_volume_owner(frame.PROBE_VOLUMES[:], edge) != 0)
}

@(test)
scene_probe_names_are_validated :: proc(t: ^testing.T) {
	testing.expect(t, frame.scene_probe_name_valid(""))
	testing.expect(t, frame.scene_probe_name_valid("room-a"))
	testing.expect(t, !frame.scene_probe_name_valid("room a"))
	testing.expect(t, !frame.scene_probe_name_valid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
}

@(test)
sealed_pair_probes_sit_in_room_air :: proc(t: ^testing.T) {
	scenario, load_error := harness.scenario_load(SEALED_SCENARIO, context.allocator)
	if load_error != "" {
		testing.expectf(t, false, "cannot load %s: %s", SEALED_SCENARIO, load_error)
		return
	}
	defer harness.scenario_destroy(&scenario, context.allocator)

	extras: []frame.Scene_Probe_Volume
	for command in scenario.commands {
		if command.kind == .Scene && command.scene.has_probe_volumes {
			extras = command.scene.scene.probe_volumes
		}
	}
	testing.expect_value(t, len(extras), 2)
	if len(extras) != 2 {
		return
	}

	air_low := [2][3]f32 {
		{-13.75, 0, -9.75},
		{-9.75, 0, -9.75},
	}
	air_high := [2][3]f32 {
		{-10.25, 3.0, -6.25},
		{-6.25, 3.0, -6.25},
	}
	for extra in extras {
		for z in 0 ..< int(extra.counts.z) {
			for y in 0 ..< int(extra.counts.y) {
				for x in 0 ..< int(extra.counts.x) {
					centre := extra.min + ([3]f32{f32(x), f32(y), f32(z)} + 0.5) * extra.spacing
					in_air := false
					for room in 0 ..< 2 {
						low := air_low[room]
						high := air_high[room]
						if centre.x > low.x && centre.x < high.x &&
						   centre.y > low.y && centre.y < high.y &&
						   centre.z > low.z && centre.z < high.z {
							in_air = true
						}
					}
					testing.expectf(t, in_air, "pair probe %v is not in room air", centre)
					testing.expectf(
						t,
						abs(centre.x + 10.0) > 0.25,
						"pair probe %v is inside the shared wall",
						centre,
					)
				}
			}
		}
	}
}
