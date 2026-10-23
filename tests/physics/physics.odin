#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package physics

import "core:testing"
import b3 "libs:box3d"

// The Box3D hello world scene. A cube falls onto a static slab and comes to
// rest at y = 1.
//
// This test guards the pair of bindings and library. If the struct layouts
// drift, the cube falls through the slab, rests at the wrong height, or the
// calls crash.
@(test)
box3d_hello_world_settles_on_ground :: proc(t: ^testing.T) {
	world_def := b3.DefaultWorldDef()
	world_def.gravity = {0, -10, 0}
	world_id := b3.CreateWorld(world_def)
	defer b3.DestroyWorld(world_id)
	testing.expect(t, b3.World_IsValid(world_id), "world is invalid")

	// Static slab. Its top face is at y = 0.
	ground_def := b3.DefaultBodyDef()
	ground_def.position = {0, -10, 0}
	ground_id := b3.CreateBody(world_id, ground_def)

	ground_hull := b3.MakeBoxHull(50, 10, 50)
	ground_shape_def := b3.DefaultShapeDef()
	ground_shape := b3.CreateHullShape(ground_id, ground_shape_def, &ground_hull.base)

	testing.expect(t, b3.Shape_IsValid(ground_shape), "ground shape is invalid")
	testing.expect_value(t, b3.Body_GetShapeCount(ground_id), 1)

	// Dynamic cube, one metre above the slab.
	body_def := b3.DefaultBodyDef()
	body_def.type = .dynamicBody
	body_def.position = {0, 4, 0}
	body_id := b3.CreateBody(world_id, body_def)

	cube_hull := b3.MakeCubeHull(1)
	shape_def := b3.DefaultShapeDef()
	shape_def.density = 1
	cube_shape := b3.CreateHullShape(body_id, shape_def, &cube_hull.base)

	testing.expect(t, b3.Shape_IsValid(cube_shape), "cube shape is invalid")
	testing.expect_value(t, b3.Body_GetShapeCount(body_id), 1)
	testing.expect_value(t, b3.Body_GetType(body_id), b3.BodyType.dynamicBody)

	for _ in 0 ..< 120 {
		b3.World_Step(world_id, 1.0 / 60.0, 4)
	}

	pos := b3.Body_GetPosition(body_id)
	testing.expectf(t, abs(pos.y - 1) < 0.01, "rest height is %v, want 1", pos.y)
	testing.expectf(t, abs(pos.x) < 0.05, "x drift is %v", pos.x)
	testing.expectf(t, abs(pos.z) < 0.05, "z drift is %v", pos.z)
}
