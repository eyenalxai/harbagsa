#+vet explicit-allocators
package game

import b3 "libs:box3d"

@(private)
create_box_body :: proc(
	world_id: b3.WorldId,
	type: b3.BodyType,
	center: b3.Vec3,
	rotation: b3.Quat,
	half_extents: [3]f32,
	density: f32,
) -> b3.BodyId {
	body_def := b3.DefaultBodyDef()
	body_def.type = type
	body_def.position = center
	body_def.rotation = rotation
	body_id := b3.CreateBody(world_id, body_def)
	if !b3.Body_IsValid(body_id) {
		return {}
	}

	hull := b3.MakeBoxHull(half_extents.x, half_extents.y, half_extents.z)
	shape_def := b3.DefaultShapeDef()
	shape_def.density = density
	shape := b3.CreateHullShape(body_id, shape_def, &hull.base)
	if !b3.Shape_IsValid(shape) {
		b3.DestroyBody(body_id)
		return {}
	}
	return body_id
}
