#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:testing"

import b3 "libs:box3d"
import game "src:game"

@(private)
place_lamp :: proc(
	sim: ^game.Simulation,
	dm: ^game.Debug_Mode,
	center: b3.Vec3,
	light: game.Light_Settings,
) -> game.Object_Id {
	return game.debug_place_object(
		dm,
		sim,
		{prefab = .Lamp, body_mode = .Static, center = center, yaw = 0, light = light},
	)
}

@(test)
lamp_placement_sticks_until_the_prefab_changes :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	game.debug_palette_open(&dm)
	testing.expect(t, game.debug_palette_select(&dm, int(game.Prefab_Id.Lamp)), "select failed")
	testing.expect_value(t, dm.palette.light.color, game.Light_Color.Warm)

	testing.expect(t, game.debug_light_change(&dm, &sim, .Color), "colour change failed")
	testing.expect(t, game.debug_light_change(&dm, &sim, .Intensity_Up), "intensity change failed")
	testing.expect(t, game.debug_light_change(&dm, &sim, .Intensity_Up), "intensity change failed")
	testing.expect(t, game.debug_light_change(&dm, &sim, .Range_Up), "range change failed")
	testing.expect(t, game.debug_light_change(&dm, &sim, .Range_Up), "range change failed")
	testing.expect_value(t, dm.palette.light.color, game.Light_Color.Cool)
	expect_near(t, dm.palette.light.intensity, 1.9, 0.0001, "tuned intensity")
	expect_near(t, dm.palette.light.range, 10.0, 0.0001, "tuned range")

	first := place_lamp(&sim, &dm, {2, 0.25, 9}, dm.palette.light)
	second := place_lamp(&sim, &dm, {4, 0.25, 9}, dm.palette.light)
	placed := [2]game.Object_Id{first, second}
	for id in placed {
		object, found := game.simulation_object_find(&sim, id)
		testing.expect(t, found, "lamp did not place")
		testing.expect_value(t, object.light.color, game.Light_Color.Cool)
		expect_near(t, object.light.intensity, 1.9, 0.0001, "placed intensity")
		expect_near(t, object.light.range, 10.0, 0.0001, "placed range")
		testing.expect_value(
			t,
			game.simulation_object_box(&sim, id).color,
			game.light_color4(game.Light_Color.Cool),
		)
		testing.expect(t, game.simulation_object_box(&sim, id).emissive > 0, "lamp is not emissive")
	}

	testing.expect(t, game.debug_palette_select(&dm, int(game.Prefab_Id.Crate)), "crate select failed")
	testing.expect(t, game.debug_palette_select(&dm, int(game.Prefab_Id.Lamp)), "lamp select failed")
	testing.expect_value(t, dm.palette.light.color, game.Light_Color.Warm)
	expect_near(t, dm.palette.light.intensity, 1.5, 0.0001, "default intensity restored")
	expect_near(t, dm.palette.light.range, 8.0, 0.0001, "default range restored")

	third := place_lamp(&sim, &dm, {6, 0.25, 9}, dm.palette.light)
	object, _ := game.simulation_object_find(&sim, third)
	testing.expect_value(t, object.light.color, game.Light_Color.Warm)
	expect_near(t, object.light.intensity, 1.5, 0.0001, "default placed intensity")
}

@(test)
intensity_and_range_steps_clamp_at_their_limits :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	game.debug_palette_open(&dm)
	testing.expect(t, game.debug_palette_select(&dm, int(game.Prefab_Id.Lamp)), "select failed")

	for _ in 0 ..< 20 {
		_ = game.debug_light_change(&dm, &sim, .Intensity_Down)
	}
	expect_near(t, dm.palette.light.intensity, game.LIGHT_INTENSITY_MIN, 0.0001, "intensity floor")
	for _ in 0 ..< 40 {
		_ = game.debug_light_change(&dm, &sim, .Intensity_Up)
	}
	expect_near(t, dm.palette.light.intensity, game.LIGHT_INTENSITY_MAX, 0.0001, "intensity ceiling")

	for _ in 0 ..< 40 {
		_ = game.debug_light_change(&dm, &sim, .Range_Down)
	}
	expect_near(t, dm.palette.light.range, game.LIGHT_RANGE_MIN, 0.0001, "range floor")
	for _ in 0 ..< 40 {
		_ = game.debug_light_change(&dm, &sim, .Range_Up)
	}
	expect_near(t, dm.palette.light.range, game.LIGHT_RANGE_MAX, 0.0001, "range ceiling")

	testing.expect(t, game.debug_light_change(&dm, &sim, .Color), "colour change failed")
	testing.expect_value(t, dm.palette.light.color, game.Light_Color.Cool)
}

@(test)
selected_lamp_edits_and_undoes_its_light :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	id := place_lamp(&sim, &dm, {2, 0.25, 9}, {})
	game.debug_palette_close(&dm)
	testing.expect(t, game.debug_select_object(&dm, &sim, id), "select failed")
	testing.expect_value(t, game.debug_history_depth(&dm), 1)

	testing.expect(t, game.debug_light_change(&dm, &sim, .Color), "colour edit failed")
	testing.expect_value(t, game.debug_history_depth(&dm), 2)
	object, _ := game.simulation_object_find(&sim, id)
	testing.expect_value(t, object.light.color, game.Light_Color.Cool)

	testing.expect(t, game.debug_light_change(&dm, &sim, .Intensity_Up), "intensity edit failed")
	testing.expect_value(t, game.debug_history_depth(&dm), 3)
	testing.expect(t, game.debug_undo(&dm, &sim), "undo failed")
	object, _ = game.simulation_object_find(&sim, id)
	testing.expect_value(t, object.light.color, game.Light_Color.Cool)
	expect_near(t, object.light.intensity, 1.5, 0.0001, "undo kept the intensity")

	testing.expect(t, game.debug_undo(&dm, &sim), "undo failed")
	object, _ = game.simulation_object_find(&sim, id)
	testing.expect_value(t, object.light.color, game.Light_Color.Warm)
	testing.expect(t, game.debug_redo(&dm, &sim), "redo failed")
	object, _ = game.simulation_object_find(&sim, id)
	testing.expect_value(t, object.light.color, game.Light_Color.Cool)
}

@(test)
non_lamp_selection_ignores_the_light_keys :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	id := first_object_id(&sim)
	testing.expect(t, game.debug_select_object(&dm, &sim, id), "select failed")
	testing.expect(t, !game.debug_light_change(&dm, &sim, .Color), "a crate accepted a light key")
	testing.expect_value(t, game.debug_history_depth(&dm), 0)

	game.debug_palette_open(&dm)
	testing.expect(t, game.debug_palette_select(&dm, int(game.Prefab_Id.Block)), "select failed")
	testing.expect(t, !game.debug_light_change(&dm, &sim, .Range_Up), "a block accepted a light key")
}

@(test)
light_values_survive_a_history_restore_with_the_same_id :: proc(t: ^testing.T) {
	sim, dm := object_editor_setup(t)
	defer game.debug_mode_destroy(&dm)
	defer game.simulation_destroy(&sim)

	id := place_lamp(&sim, &dm, {2, 0.25, 9}, game.light_settings(.Blue, 2.6, 13.0))
	game.debug_palette_close(&dm)
	step_world(&sim, 30)
	before := game.simulation_object_box(&sim, id)

	testing.expect(t, game.debug_move_selected(&dm, &sim, {5, 0.25, 9}), "move failed")
	testing.expect(t, game.debug_undo(&dm, &sim), "undo failed")
	restored := game.simulation_object_box(&sim, id)
	testing.expect_value(t, restored.center, before.center)
	object, found := game.simulation_object_find(&sim, id)
	testing.expect(t, found, "the restore lost the id")
	testing.expect_value(t, object.light.color, game.Light_Color.Blue)
	expect_near(t, object.light.intensity, 2.6, 0.0001, "restored intensity")
	expect_near(t, object.light.range, 13.0, 0.0001, "restored range")
	testing.expect_value(t, game.simulation_object_scale(&sim, id), 1.0)
	testing.expect_value(t, game.simulation_object_spawn_age(&sim, id), 0.0)
}

@(test)
the_eight_nearest_lamps_win_with_a_stable_order :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	positions := []f32{1.0, -1.0, 2.0, -2.0, 3.0, -3.0, 4.0, -4.0, 5.0, 6.0}
	ids: [10]game.Object_Id
	for x, index in positions {
		ids[index] = game.simulation_create_object(
			&sim,
			{prefab = .Lamp, body_mode = .Static, center = {x, 1.0, 0.0}, yaw = 0},
		)
	}
	testing.expect_value(t, game.simulation_lamp_count(&sim), 10)
	testing.expect_value(t, game.simulation_active_light_count(&sim), game.MAX_ACTIVE_LIGHTS)

	camera := b3.Vec3{0, 1, 0}
	active := game.simulation_collect_lights(&sim, camera)
	testing.expect_value(t, active.count, game.MAX_ACTIVE_LIGHTS)
	for index in 0 ..< active.count {
		testing.expect_value(t, active.lights[index].object_id, ids[index])
	}

	again := game.simulation_collect_lights(&sim, camera)
	for index in 0 ..< active.count {
		testing.expect_value(t, again.lights[index].object_id, active.lights[index].object_id)
	}

	beside := game.simulation_collect_lights(&sim, b3.Vec3{6, 1, 0})
	testing.expect_value(t, beside.lights[0].object_id, ids[9])
	last := beside.lights[beside.count - 1]
	testing.expectf(t, last.object_id == ids[3], "the close camera kept %v", last.object_id)
}
