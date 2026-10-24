#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package simulation

import "core:math"
import "core:testing"

import b3 "libs:box3d"
import game "src:game"

@(test)
prefab_catalog_has_the_eleven_boxes :: proc(t: ^testing.T) {
	testing.expect_value(t, len(game.PREFABS), 11)
	for prefab in game.Prefab_Id {
		info := game.prefab(prefab)
		testing.expectf(t, info.name != "", "prefab %v has no name", prefab)
		testing.expectf(
			t,
			info.half_extents.x > 0.0 && info.half_extents.y > 0.0 && info.half_extents.z > 0.0,
			"prefab %v has an empty box",
			prefab,
		)
		testing.expectf(t, info.density > 0.0, "prefab %v has no density", prefab)
	}

	testing.expect_value(t, game.prefab(.Crate).body_mode, game.Body_Mode.Dynamic)
	testing.expect_value(t, game.prefab(.Small_Crate).body_mode, game.Body_Mode.Dynamic)
	testing.expect_value(t, game.prefab(.Wide_Crate).body_mode, game.Body_Mode.Dynamic)
	testing.expect_value(t, game.prefab(.Block).body_mode, game.Body_Mode.Static)
	testing.expect_value(t, game.prefab(.Platform).body_mode, game.Body_Mode.Static)
	testing.expect_value(t, game.prefab(.Ramp).body_mode, game.Body_Mode.Static)
	testing.expect_value(t, game.prefab(.Pillar).body_mode, game.Body_Mode.Static)
	testing.expect_value(t, game.prefab(.Wall).body_mode, game.Body_Mode.Static)
	testing.expect_value(t, game.prefab(.Lamp).body_mode, game.Body_Mode.Static)
	testing.expect_value(t, game.prefab(.Light_Panel).body_mode, game.Body_Mode.Static)
	testing.expect_value(t, game.prefab(.Beacon).body_mode, game.Body_Mode.Static)

	testing.expect_value(t, game.prefab(.Crate).color, game.CRATE_GREEN_COLOR)
	testing.expect_value(t, game.prefab(.Small_Crate).color, game.CRATE_AMBER_COLOR)
	testing.expect_value(t, game.prefab(.Wide_Crate).color, game.CRATE_BLUE_COLOR)
	testing.expect_value(t, game.prefab(.Crate).half_extents, [3]f32{0.5, 0.5, 0.5})
	testing.expect_value(t, game.prefab(.Small_Crate).half_extents, [3]f32{0.25, 0.25, 0.25})
	testing.expect_value(t, game.prefab(.Wide_Crate).half_extents, [3]f32{1.0, 0.5, 0.5})
	testing.expect_value(t, game.prefab(.Block).half_extents, [3]f32{1.0, 0.5, 1.0})
	testing.expect_value(t, game.prefab(.Platform).half_extents, [3]f32{2.0, 0.25, 2.0})
	testing.expect_value(t, game.prefab(.Ramp).half_extents, [3]f32{1.0, 0.25, 1.5})
	testing.expect_value(t, game.prefab(.Pillar).half_extents, [3]f32{0.25, 1.5, 0.25})
	testing.expect_value(t, game.prefab(.Wall).half_extents, [3]f32{2.0, 1.5, 0.25})
	testing.expect_value(t, game.prefab(.Lamp).half_extents, [3]f32{0.25, 0.25, 0.25})
	testing.expect_value(t, game.prefab(.Light_Panel).half_extents, [3]f32{1.0, 0.05, 0.25})
	testing.expect_value(t, game.prefab(.Beacon).half_extents, [3]f32{0.15, 0.15, 0.15})
	expect_near(t, game.prefab(.Ramp).base_pitch, 20.0 * math.PI / 180.0, 0.0001, "ramp pitch")

	testing.expect_value(t, game.prefab_light(.Lamp).color, game.Light_Color.Warm)
	testing.expect_value(t, game.prefab_light(.Lamp).intensity, 1.5)
	testing.expect_value(t, game.prefab_light(.Lamp).range, 8.0)
	testing.expect_value(t, game.prefab_light(.Light_Panel).color, game.Light_Color.Cool)
	testing.expect_value(t, game.prefab_light(.Light_Panel).intensity, 1.2)
	testing.expect_value(t, game.prefab_light(.Light_Panel).range, 10.0)
	testing.expect_value(t, game.prefab_light(.Beacon).color, game.Light_Color.Red)
	testing.expect_value(t, game.prefab_light(.Beacon).intensity, 2.0)
	testing.expect_value(t, game.prefab_light(.Beacon).range, 5.0)
	for prefab in game.Prefab_Id {
		if game.prefab_has_light(prefab) {
			testing.expectf(t, game.prefab_light(prefab).emissive > 0, "prefab %v has no glow", prefab)
		}
	}
}

@(test)
starting_scene_has_three_crate_objects :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	objects := game.simulation_objects(&sim)
	colors := game.INITIAL_CRATE_COLORS
	testing.expect_value(t, len(objects), game.INITIAL_CRATE_COUNT)
	for position, index in game.INITIAL_CRATE_POSITIONS {
		object := objects[index]
		testing.expect_value(t, object.id, game.Object_Id(index + 1))
		testing.expect_value(t, object.prefab, game.Prefab_Id.Crate)
		testing.expect_value(t, object.body_mode, game.Body_Mode.Dynamic)

		box := game.simulation_object_box(&sim, object.id)
		testing.expect_value(t, box.center, position)
		testing.expect_value(t, box.half_extents, game.prefab(.Crate).half_extents)
		testing.expect_value(t, box.color, colors[index])
	}
}

@(test)
ramp_prefab_applies_its_base_pitch :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	id := game.simulation_create_object(
		&sim,
		{prefab = .Ramp, body_mode = .Static, center = {0, 5, 0}, yaw = 0},
	)
	rotation := game.simulation_object_box(&sim, id).rotation
	expected := b3.MakeQuatFromAxisAngle({1, 0, 0}, game.RAMP_BASE_PITCH)
	expect_near(t, rotation.x, expected.x, 0.0001, "ramp pitch x")
	expect_near(t, rotation.w, expected.w, 0.0001, "ramp pitch w")
}

@(test)
every_prefab_creates_the_requested_body :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	created := 0
	for prefab in game.Prefab_Id {
		for mode in game.Body_Mode {
			center := b3.Vec3{f32(created) * 3.0 + 20.0, 20.0, 0.0}
			id := game.simulation_create_object(
				&sim,
				{prefab = prefab, body_mode = mode, center = center, yaw = 0.25},
			)
			testing.expectf(t, id != game.INVALID_OBJECT_ID, "prefab %v did not create", prefab)
			if id == game.INVALID_OBJECT_ID {
				continue
			}

			object, found := game.simulation_object_find(&sim, id)
			testing.expect(t, found, "created object is not findable")
			testing.expect_value(t, object.prefab, prefab)
			testing.expect_value(t, object.body_mode, mode)
			testing.expect_value(
				t,
				b3.Body_GetType(object.body),
				mode == game.Body_Mode.Static ? b3.BodyType.staticBody : b3.BodyType.dynamicBody,
			)

			box := game.simulation_object_box(&sim, id)
			testing.expect_value(t, box.half_extents, game.prefab(prefab).half_extents)
			testing.expect_value(t, box.color, game.prefab_color(prefab))
			testing.expect_value(t, object.light.active, game.prefab_has_light(prefab))
			created += 1
		}
	}

	testing.expect_value(t, created, 22)
	testing.expect_value(
		t,
		game.simulation_object_count(&sim),
		game.INITIAL_CRATE_COUNT + created,
	)
}

@(test)
create_object_past_cap_is_ignored :: proc(t: ^testing.T) {
	sim := create(t)
	defer game.simulation_destroy(&sim)

	for game.simulation_object_count(&sim) < game.MAX_PLACED_OBJECTS {
		_ = game.simulation_create_object(
			&sim,
			{
				prefab = .Block,
				body_mode = .Static,
				center = {0, -5, 0},
				yaw = 0,
			},
		)
	}
	testing.expect_value(t, game.simulation_object_count(&sim), game.MAX_PLACED_OBJECTS)

	id := game.simulation_create_object(
		&sim,
		{prefab = .Crate, body_mode = .Dynamic, center = {0, 50, 0}, yaw = 0},
	)
	testing.expect_value(t, id, game.INVALID_OBJECT_ID)
	testing.expect_value(t, game.simulation_object_count(&sim), game.MAX_PLACED_OBJECTS)
}
