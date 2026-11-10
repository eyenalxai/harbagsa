#+vet explicit-allocators
package frame

import b3 "libs:box3d"

import "src:game"
import "src:geometry"
import "src:renderer"

// The spider is ordinary boxes. Frame building interpolates the body and the foot
// targets, then solves the two-bone IK at render rate, so planted feet stay
// still while the body moves between fixed steps.
spider_boxes :: proc(
	boxes: ^[dynamic]renderer.Frame_Box,
	snapshot: game.Render_Snapshot,
	alpha: f32,
) {
	start := len(boxes^)
	weight := clamp(alpha, 0.0, 1.0)
	feet :=
		snapshot.previous_position + (snapshot.position - snapshot.previous_position) * weight
	body_yaw :=
		snapshot.previous_body_yaw +
		b3.UnwindAngle(snapshot.body_yaw - snapshot.previous_body_yaw) * weight
	center := feet + b3.Vec3{0.0, game.SPIDER_BODY_HEIGHT, 0.0}
	rotation := game.yaw_quaternion(body_yaw)

	append(
		boxes,
		renderer.Frame_Box {
			box = geometry.Box {
				center = center + game.rotate_yaw(game.SPIDER_CEPHALOTHORAX_OFFSET, body_yaw),
				half_extents = game.SPIDER_CEPHALOTHORAX_HALF,
				color = game.SPIDER_CEPHALOTHORAX_COLOR,
				rotation = rotation,
			},
			identity = renderer.Spider_Box_Identity{index = len(boxes^) - start},
		},
	)
	append(
		boxes,
		renderer.Frame_Box {
			box = geometry.Box {
				center = center + game.rotate_yaw(game.SPIDER_ABDOMEN_OFFSET, body_yaw),
				half_extents = game.SPIDER_ABDOMEN_HALF,
				color = game.SPIDER_ABDOMEN_COLOR,
				rotation = rotation,
			},
			identity = renderer.Spider_Box_Identity{index = len(boxes^) - start},
		},
	)

	for eye in game.SPIDER_EYES {
		append(
			boxes,
			renderer.Frame_Box {
				box = geometry.Box {
					center = center + game.rotate_yaw(eye, body_yaw),
					half_extents = {0.035, 0.030, 0.025},
					color = game.SPIDER_EYE_COLOR,
					rotation = rotation,
					emissive = game.SPIDER_EYE_EMISSIVE,
				},
				identity = renderer.Spider_Box_Identity{index = len(boxes^) - start},
			},
		)
	}
	for mark in game.SPIDER_MARKS {
		append(
			boxes,
			renderer.Frame_Box {
				box = geometry.Box {
					center = center + game.rotate_yaw(mark, body_yaw),
					half_extents = {0.20, 0.012, 0.026},
					color = game.SPIDER_MARK_COLOR,
					rotation = rotation,
					emissive = game.SPIDER_MARK_EMISSIVE,
				},
				identity = renderer.Spider_Box_Identity{index = len(boxes^) - start},
			},
		)
	}

	for index in 0 ..< game.LEG_COUNT {
		leg := snapshot.legs[index]
		hip := center + game.rotate_yaw(game.LEG_HIPS[index], body_yaw)
		foot := leg.previous_foot + (leg.foot - leg.previous_foot) * weight
		pole := game.rotate_yaw(game.spider_pole_hint(game.LEG_HIPS[index]), body_yaw)
		knee, reached := game.spider_leg_ik(hip, foot, pole)

		append(boxes, renderer.Frame_Box {
			box = geometry.box_between(hip, knee, game.LEG_THICKNESS, game.SPIDER_LEG_COLOR),
			identity = renderer.Spider_Box_Identity{index = len(boxes^) - start},
		})
		append(
			boxes,
			renderer.Frame_Box {
				box = geometry.box_between(
					knee,
					reached,
					game.LEG_THICKNESS * 0.78,
					game.SPIDER_LEG_COLOR,
				),
				identity = renderer.Spider_Box_Identity{index = len(boxes^) - start},
			},
		)
		append(
			boxes,
			renderer.Frame_Box {
				box = geometry.Box {
					center = knee,
					half_extents = {game.LEG_KNEE_HALF, game.LEG_KNEE_HALF, game.LEG_KNEE_HALF},
					color = game.SPIDER_KNEE_COLOR,
					rotation = rotation,
				},
				identity = renderer.Spider_Box_Identity{index = len(boxes^) - start},
			},
		)
	}
}
