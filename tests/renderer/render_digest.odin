#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package renderer_test

import "core:reflect"
import "core:testing"

import "src:digest"
import "src:geometry"
import "src:renderer"

DIGEST_CAMERA :: renderer.Camera {
	position = {1, 2, 3},
	yaw      = 0.5,
	pitch    = -0.25,
	fov_x    = 1.5,
}

digest_input :: proc() -> renderer.Render_Input {
	return {
		width = 320,
		height = 180,
		camera = DIGEST_CAMERA,
		boxes = {},
		lights = {},
		jitter = {0.001, -0.002},
		atlas_weight = 400,
		view_flags = {.HUD, .Debug_Draw},
	}
}

@(test)
render_digest_is_stable_for_the_same_inputs :: proc(t: ^testing.T) {
	input := digest_input()
	first := renderer.render_digest(input)
	second := renderer.render_digest(input)
	testing.expect_value(t, first.value, second.value)
}

@(test)
render_digest_changes_with_each_render_input :: proc(t: ^testing.T) {
	base := digest_input()
	baseline := renderer.render_digest(base)

	camera := base
	camera.camera.position.x += 0.5
	testing.expect(t, renderer.render_digest(camera).value != baseline.value, "camera did not change the digest")

	boxes := base
	boxes.boxes = []geometry.Box {
		{center = {1, 2, 3}, half_extents = {0.5, 0.5, 0.5}, color = {1, 0, 0, 1}},
	}
	boxes_digest := renderer.render_digest(boxes).value
	testing.expect(t, boxes_digest != baseline.value, "boxes did not change the digest")

	boxes.boxes[0].color.g = 1
	testing.expect(
		t,
		renderer.render_digest(boxes).value != boxes_digest,
		"box color did not change the digest",
	)

	emissive_digest := renderer.render_digest(boxes).value
	boxes.boxes[0].emissive = 1
	testing.expect(
		t,
		renderer.render_digest(boxes).value != emissive_digest,
		"box emissive did not change the digest",
	)

	lights := base
	lights.lights = []renderer.Light {
		{position = {1, 2, 3}, intensity = 2, color = {1, 0.5, 0.25}, range = 8},
	}
	lights_digest := renderer.render_digest(lights).value
	testing.expect(t, lights_digest != baseline.value, "lights did not change the digest")

	lights.lights[0].intensity = 3
	testing.expect(
		t,
		renderer.render_digest(lights).value != lights_digest,
		"light intensity did not change the digest",
	)

	lights.lights[0].intensity = 2
	lights.lights[0].range = 9
	testing.expect(
		t,
		renderer.render_digest(lights).value != lights_digest,
		"light range did not change the digest",
	)

	jitter := base
	jitter.jitter.x += 0.01
	testing.expect(t, renderer.render_digest(jitter).value != baseline.value, "jitter did not change the digest")

	weight := base
	weight.atlas_weight = 900
	testing.expect(t, renderer.render_digest(weight).value != baseline.value, "atlas weight did not change the digest")

	clip := base
	clip.clip_height = 4
	testing.expect(t, renderer.render_digest(clip).value != baseline.value, "clip height did not change the digest")

	shadows := base
	shadows.light_shadows = true
	testing.expect(t, renderer.render_digest(shadows).value != baseline.value, "shadows did not change the digest")

	view := base
	view.view_flags = {.HUD}
	testing.expect(t, renderer.render_digest(view).value != baseline.value, "view flags did not change the digest")
}

@(test)
state_digest_algorithm_is_stable :: proc(t: ^testing.T) {
	hash := digest.fnv()
	text := digest.hex(hash, context.temp_allocator)
	testing.expect_value(t, text, "cbf29ce484222325")
}

@(test)
render_input_gains_a_digest_row_with_every_field :: proc(t: ^testing.T) {
	fields := reflect.struct_fields_zipped(renderer.Render_Input)
	testing.expect_value(t, len(renderer.RENDER_DIGEST_FIELDS), len(fields))
	for field in fields {
		found := false
		for row in renderer.RENDER_DIGEST_FIELDS {
			if row.name == field.name {
				found = true
				break
			}
		}
		testing.expectf(t, found, "Render_Input.%s has no digest row", field.name)
	}
	for row in renderer.RENDER_DIGEST_FIELDS {
		if !row.hashed {
			testing.expectf(t, row.reason != "", "unhashed input %q has no reason", row.name)
		}
	}
}
