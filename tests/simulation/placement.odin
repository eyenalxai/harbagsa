#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:math"
import "core:testing"

import b3 "libs:box3d"
import game "src:game"

PLACEMENT_FLOOR_PITCH :: -0.9
PLACEMENT_HIGH_PITCH :: 0.6

@(private)
placement_setup :: proc(t: ^testing.T) -> (game.Simulation, game.Debug_Mode) {
	sim, dm := object_editor_setup(t)
	dm.camera.pitch = PLACEMENT_FLOOR_PITCH
	return sim, dm
}

@(private)
placement_arm :: proc(t: ^testing.T, dm: ^game.Debug_Mode, sim: ^game.Simulation, id: game.Prefab_Id) {
	apply_expect(t, dm, sim, game.Placement_Arm{prefab = id}, "arm failed")
}

@(test)
palette_pick_arms_the_selected_prefab :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	apply_expect(t, &dm, &sim, game.Palette_Open{}, "open failed")
	testing.expect(t, dm.palette.open, "palette did not open")
	apply_expect(t, &dm, &sim, game.Palette_Select{index = 4}, "platform select failed")
	apply_expect(t, &dm, &sim, game.Palette_Pick{}, "pick failed")

	testing.expect(t, !dm.palette.open, "pick left the palette open")
	testing.expect(t, dm.placement.armed, "pick did not arm the placement")
	testing.expect_value(t, dm.placement.prefab, game.Prefab_Id.Platform)
	testing.expect_value(t, dm.palette.body_mode, game.Body_Mode.Static)
}

@(test)
palette_body_defaults_from_the_prefab_and_sticks_until_changed :: proc(t: ^testing.T) {
	dm := game.debug_mode_create(context.allocator)
	dm.active = true
	defer game.debug_mode_destroy(&dm)
	testing.expect_value(t, dm.palette.body_mode, game.Body_Mode.Dynamic)

	apply_expect(t, &dm, nil, game.Flip_Body{}, "flip failed")
	testing.expect_value(t, dm.palette.body_mode, game.Body_Mode.Static)
	apply_expect(t, &dm, nil, game.Palette_Select{index = 5}, "ramp select failed")
	testing.expect_value(t, dm.palette.body_mode, game.Body_Mode.Static)

	apply_expect(t, &dm, nil, game.Palette_Select{index = 0}, "crate select failed")
	testing.expect_value(t, dm.palette.body_mode, game.Body_Mode.Dynamic)
	apply_expect(t, &dm, nil, game.Flip_Body{}, "flip failed")
	apply_expect(t, &dm, nil, game.Palette_Select{index = 0}, "repeat select failed")
	testing.expect_value(t, dm.palette.body_mode, game.Body_Mode.Static)
	testing.expect(t, !apply(&dm, nil, game.Palette_Select{index = game.PREFAB_COUNT}).applied, "bad index accepted")
}

@(test)
placement_ray_puts_the_aabb_bottom_on_the_hit :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Block)

	anchor := dm.placement.anchor
	expect_near(t, anchor.y, 0.0, 0.001, "ray did not hit the floor")
	ghost, ok := game.debug_ghost_geometry(&dm)
	testing.expect(t, ok, "armed ghost has no geometry")
	expect_near(t, ghost.bottom.x, anchor.x, 0.0001, "bottom x")
	expect_near(t, ghost.bottom.y, anchor.y, 0.0001, "bottom y")
	expect_near(t, ghost.bottom.z, anchor.z, 0.0001, "bottom z")
	expect_near(
		t,
		ghost.center.y - ghost.bottom.y,
		game.prefab(.Block).half_extents.y,
		0.0001,
		"aabb half height",
	)
}

@(test)
placement_ray_miss_uses_the_fallback_distance :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)
	dm.camera.pitch = PLACEMENT_HIGH_PITCH
	placement_arm(t, &dm, &sim, .Crate)

	expected := dm.camera.position +
	            game.debug_camera_forward(dm.camera) * game.PLACEMENT_FALLBACK_DISTANCE
	expect_near(t, dm.placement.anchor.x, expected.x, 0.0001, "fallback x")
	expect_near(t, dm.placement.anchor.y, expected.y, 0.0001, "fallback y")
	expect_near(t, dm.placement.anchor.z, expected.z, 0.0001, "fallback z")
}

@(test)
placement_height_steps_and_clamps_to_the_surface :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Crate)

	apply_expect(t, &dm, &sim, game.Placement_Raise{steps = 1})
	expect_near(t, dm.placement.height, 0.25, 0.0001, "single height step")
	apply_expect(t, &dm, &sim, game.Placement_Raise{steps = 1, large = true})
	expect_near(t, dm.placement.height, 1.25, 0.0001, "large height step")

	apply_expect(t, &dm, &sim, game.Placement_Raise{steps = -100, large = true})
	expect_near(t, dm.placement.height, 0.0, 0.0001, "height floor")
	ghost, _ := game.debug_ghost_geometry(&dm)
	testing.expect(t, ghost.bottom.y >= ghost.surface.y, "ghost sank below its surface")
}

@(test)
placement_yaw_steps_fifteen_and_forty_five_degrees :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Crate)

	apply_expect(t, &dm, &sim, game.Placement_Turn{steps = 1})
	expect_near(t, dm.placement.yaw_degrees, 15.0, 0.0001, "yaw step")
	apply_expect(t, &dm, &sim, game.Placement_Turn{steps = 1, large = true})
	expect_near(t, dm.placement.yaw_degrees, 60.0, 0.0001, "large yaw step")
	apply_expect(t, &dm, &sim, game.Placement_Turn{steps = -4})
	expect_near(t, dm.placement.yaw_degrees, 0.0, 0.0001, "yaw back to zero")
	apply_expect(t, &dm, &sim, game.Placement_Turn{steps = -1})
	expect_near(t, dm.placement.yaw_degrees, 345.0, 0.0001, "yaw wrap")
}

@(test)
placement_rotation_composes_yaw_and_base_pitch :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Ramp)
	apply_expect(t, &dm, &sim, game.Placement_Set_Yaw{yaw_deg = 90.0})

	ghost, _ := game.debug_ghost_geometry(&dm)
	expected := b3.MulQuat(
		b3.MakeQuatFromAxisAngle({0.0, 1.0, 0.0}, math.PI * 0.5),
		b3.MakeQuatFromAxisAngle({1.0, 0.0, 0.0}, game.RAMP_BASE_PITCH),
	)
	expect_near(t, ghost.rotation.x, expected.x, 0.0001, "rotation x")
	expect_near(t, ghost.rotation.y, expected.y, 0.0001, "rotation y")
	expect_near(t, ghost.rotation.z, expected.z, 0.0001, "rotation z")
	expect_near(t, ghost.rotation.w, expected.w, 0.0001, "rotation w")
}

@(test)
placement_snap_rounds_the_bottom_to_a_quarter_metre_grid :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Block)
	testing.expect(t, !dm.placement.snap, "snap must start off")
	dm.placement.anchor = {0.13, 0.0, 11.37}
	dm.placement.height = 0.7
	apply_expect(t, &dm, &sim, game.Placement_Toggle_Snap{})
	testing.expect(t, dm.placement.snap, "snap toggle did not turn on")

	ghost, _ := game.debug_ghost_geometry(&dm)
	expect_near(t, ghost.bottom.x, 0.25, 0.0001, "snapped x")
	expect_near(t, ghost.bottom.z, 11.25, 0.0001, "snapped z")
	expect_near(t, ghost.bottom.y, 0.7, 0.0001, "snap must not move the height")

	apply_expect(t, &dm, &sim, game.Placement_Set_Snap{snap = false})
	ghost, _ = game.debug_ghost_geometry(&dm)
	expect_near(t, ghost.bottom.x, 0.13, 0.0001, "unsnapped x")
	expect_near(t, ghost.bottom.z, 11.37, 0.0001, "unsnapped z")
}

@(test)
placement_place_creates_at_the_ghost_and_stays_armed :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)
	apply_expect(t, &dm, &sim, game.Palette_Select{index = 3}, "select failed")
	apply_expect(t, &dm, &sim, game.Palette_Pick{}, "pick failed")
	apply_expect(t, &dm, &sim, game.Placement_Set_Yaw{yaw_deg = 30.0}, "yaw failed")
	apply_expect(t, &dm, &sim, game.Placement_Set_Height{height = 0.5}, "height failed")

	ghost, _ := game.debug_ghost_geometry(&dm)
	before := game.simulation_object_count(&sim)
	result := apply(&dm, &sim, game.Placement_Place{})
	testing.expectf(t, result.applied, "place failed: %s", game.edit_reason_message(result.reason))
	id := dm.selected_object_id
	testing.expect(t, id != game.INVALID_OBJECT_ID, "place selected nothing")
	testing.expect_value(t, game.simulation_object_count(&sim), before + 1)

	object, found := game.simulation_object_find(&sim, id)
	testing.expect(t, found, "placed object is not findable")
	testing.expect_value(t, object.prefab, game.Prefab_Id.Block)
	testing.expect_value(t, object.body_mode, game.Body_Mode.Static)
	box := game.simulation_object_box(&sim, id)
	expect_near(t, box.center.x, ghost.center.x, 0.0001, "placed x")
	expect_near(t, box.center.y, ghost.center.y, 0.0001, "placed y")
	expect_near(t, box.center.z, ghost.center.z, 0.0001, "placed z")
	expect_near(t, game.simulation_object_yaw(&sim, id), math.PI / 6.0, 0.01, "placed yaw")

	testing.expect(t, dm.placement.armed, "place disarmed the tool")
	testing.expect_value(t, dm.selected_object_id, id)
}

@(test)
placement_past_the_old_cap_applies :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)
	for _ in 0 ..< 300 {
		_ = game.simulation_create_object(
			&sim,
			{prefab = .Block, body_mode = .Static, center = {0.0, -5.0, 0.0}, yaw_rad = 0.0},
		)
	}
	before := game.simulation_object_count(&sim)
	placement_arm(t, &dm, &sim, .Crate)
	dm.selection = .Object
	dm.selected_object_id = 1

	apply_expect(t, &dm, &sim, game.Placement_Place{}, "a grown scene refused a place")
	testing.expect_value(t, game.simulation_object_count(&sim), before + 1)
}

@(test)
placement_cancel_clears_the_armed_tool :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Crate)
	before := game.simulation_object_count(&sim)

	apply_expect(t, &dm, &sim, game.Placement_Cancel{}, "cancel failed")
	testing.expect(t, !dm.placement.armed, "cancel kept the tool armed")
	testing.expect_value(t, game.simulation_object_count(&sim), before)
	testing.expect(t, !apply(&dm, &sim, game.Placement_Place{}).applied, "disarmed place applied")
}

@(test)
placement_ghost_lines_draw_the_outline_footprint_and_height_guide :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)
	placement_arm(t, &dm, &sim, .Block)
	apply_expect(t, &dm, &sim, game.Placement_Set_Height{height = 0.5})

	lines: game.Debug_Lines
	game.collect_placement_lines(&dm, &lines)
	testing.expect_value(t, lines.count, 17)

	apply_expect(t, &dm, &sim, game.Placement_Cancel{}, "cancel failed")
	lines.count = 0
	game.collect_placement_lines(&dm, &lines)
	testing.expect_value(t, lines.count, 0)
}

@(test)
editor_lines_include_the_armed_ghost :: proc(t: ^testing.T) {
	sim, dm := placement_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	lines: game.Debug_Lines
	game.collect_editor_lines(&dm, &sim, &lines)
	base := lines.count
	placement_arm(t, &dm, &sim, .Block)
	apply_expect(t, &dm, &sim, game.Placement_Set_Height{height = 0.5})
	lines.count = 0
	game.collect_editor_lines(&dm, &sim, &lines)
	testing.expect_value(t, lines.count, base + 17)
}
