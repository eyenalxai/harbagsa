#+vet explicit-allocators
#+vet !unused-procedures // the harness and the scene report read the leg state
package game

import "core:math"
import b3 "libs:box3d"

// A leg holds one world foot target. A planted foot does not move between
// steps; a swinging foot follows a short arc to its next target.
Leg :: struct {
	foot:          b3.Vec3,
	previous_foot: b3.Vec3,
	swing_from:    b3.Vec3,
	swing_target:  b3.Vec3,
	swing_elapsed: f32,
	duration:      f32,
	planted:       bool,
	swinging:      bool,
}

// Body-space anchors. Local -Z is forward. The hips sit four to a side between
// the cephalothorax and the abdomen; the rest points describe the leg span.
LEG_HIPS := [LEG_COUNT]b3.Vec3 {
	{-0.26, 0.0, -0.26},
	{0.26, 0.0, -0.26},
	{-0.30, 0.0, -0.09},
	{0.30, 0.0, -0.09},
	{-0.30, 0.0, 0.09},
	{0.30, 0.0, 0.09},
	{-0.26, 0.0, 0.26},
	{0.26, 0.0, 0.26},
}

LEG_RESTS := [LEG_COUNT]b3.Vec3 {
	{-0.70, -SPIDER_BODY_HEIGHT, -0.84},
	{0.70, -SPIDER_BODY_HEIGHT, -0.84},
	{-1.00, -SPIDER_BODY_HEIGHT, -0.34},
	{1.00, -SPIDER_BODY_HEIGHT, -0.34},
	{-1.00, -SPIDER_BODY_HEIGHT, 0.30},
	{1.00, -SPIDER_BODY_HEIGHT, 0.30},
	{-0.70, -SPIDER_BODY_HEIGHT, 0.84},
	{0.70, -SPIDER_BODY_HEIGHT, 0.84},
}

// Alternating tetrapod: the front-left, rear-left, front-right, and rear-right
// legs step together, then the other four.
LEG_GROUP := [LEG_COUNT]u8{0, 1, 1, 0, 0, 1, 1, 0}

LEG_MAX_REACH :: (LEG_FEMUR_LENGTH + LEG_TIBIA_LENGTH) * LEG_REACH_FRACTION

rotate_yaw :: proc(point: b3.Vec3, yaw: f32) -> b3.Vec3 {
	c := math.cos(yaw)
	s := math.sin(yaw)
	return {point.x * c + point.z * s, point.y, -point.x * s + point.z * c}
}

body_center :: proc(player: ^Player, position: b3.Vec3) -> b3.Vec3 {
	return position + b3.Vec3{0.0, SPIDER_BODY_HEIGHT, 0.0}
}

// Two-bone IK. The knee lies on the circle where the two bones meet; the pole
// hint picks the side. An up-and-out pole makes the knee rise above the body,
// which is how an arachnid leg folds. The foot is pulled inside the reach first,
// so the chain never straightens into a lock.
spider_leg_ik :: proc(
	hip, foot, pole_hint: b3.Vec3,
	femur := LEG_FEMUR_LENGTH,
	tibia := LEG_TIBIA_LENGTH,
) -> (knee, reached: b3.Vec3) {
	offset := foot - hip
	distance := b3.Length(offset)
	if distance <= 0.0001 {
		return hip + {0.0, femur, 0.0}, hip
	}

	max_reach := (femur + tibia) * LEG_REACH_FRACTION
	min_reach := max(abs(femur - tibia) + 0.001, 0.001)
	clamped := clamp(distance, min_reach, max_reach)
	reached = hip + offset * (clamped / distance)
	direction := offset / distance

	a := (femur * femur - tibia * tibia + clamped * clamped) / (2.0 * clamped)
	height := math.sqrt(max(femur * femur - a * a, 0.0))

	pole := pole_hint - direction * b3.Dot(pole_hint, direction)
	pole_length := b3.Length(pole)
	if pole_length <= 0.0001 {
		pole = {0.0, 1.0, 0.0} - direction * direction.y
		pole_length = b3.Length(pole)
	}
	if pole_length <= 0.0001 {
		return hip + direction * a, reached
	}
	pole /= pole_length
	knee = hip + direction * a + pole * height
	return knee, reached
}

// The knee points up and away from the body, so a planted foot produces the
// familiar arachnid silhouette even when the body is close to the ground.
spider_pole_hint :: proc(hip_local: b3.Vec3) -> b3.Vec3 {
	outward := b3.Vec3{hip_local.x, 0.0, hip_local.z}
	length := b3.Length(outward)
	if length > 0.0001 {
		outward /= length
	}
	return outward * 0.55 + b3.Vec3{0.0, 1.0, 0.0}
}

@(private)
leg_ground :: proc(sim: ^Simulation, point: b3.Vec3) -> (b3.Vec3, bool) {
	origin := b3.Pos{point.x, point.y, point.z}
	ray := b3.World_CastRayClosest(
		sim.world_id,
		origin,
		b3.Vec3{0.0, -LEG_GROUND_PROBE, 0.0},
		b3.DefaultQueryFilter(),
	)
	if !ray.hit || ray.normal.y < GROUND_NORMAL_THRESHOLD {
		return {}, false
	}
	ground := b3.ToVec3(ray.point)
	return ground + b3.Vec3{0.0, LEG_PLANT_LIFT, 0.0} + ray.normal * 0.01, true
}

// A foot target is the rest point carried by the body, led by the current
// velocity so the leg lands where the body is going. The target is clamped into
// reach, because a rest point at full stride can sit past the leg length.
@(private)
spider_foot_target :: proc(sim: ^Simulation, index: int) -> (b3.Vec3, bool) {
	player := &sim.player
	center := body_center(player, player.position)
	rest := rotate_yaw(LEG_RESTS[index], player.yaw)
	lead := b3.Vec3{player.velocity.x, 0.0, player.velocity.z} * LEG_STEP_LEAD
	wanted := b3.Vec3{center.x + rest.x + lead.x, center.y + 0.9, center.z + rest.z + lead.z}
	target, hit := leg_ground(sim, wanted)
	if !hit {
		return {}, false
	}

	hip := center + rotate_yaw(LEG_HIPS[index], player.yaw)
	offset := target - hip
	distance := b3.Length(offset)
	if distance > LEG_MAX_REACH {
		// Pull the target in along the ground, not along the hip-to-foot line.
		// A 3D pull would lift a far target above the floor and plant the foot in
		// the air, which the IK then has to follow.
		vertical := offset.y
		horizontal := math.sqrt(max(LEG_MAX_REACH * LEG_MAX_REACH - vertical * vertical, 0.0))
		reach := math.sqrt(offset.x * offset.x + offset.z * offset.z)
		if reach > 0.0001 && horizontal < reach {
			scale := horizontal / reach
			target.x = hip.x + offset.x * scale
			target.z = hip.z + offset.z * scale
		}
	}
	return target, true
}

@(private)
start_swing :: proc(leg: ^Leg, from, to: b3.Vec3, duration: f32) {
	leg.swing_from = from
	leg.swing_target = to
	leg.swing_elapsed = 0.0
	leg.duration = duration
	leg.swinging = true
	leg.planted = false
}

// Places every foot on the ground under its rest point without playing a swing.
// Reset and spawn use this, so the first frame is already at rest.
spider_plant_legs :: proc(sim: ^Simulation) {
	for index in 0 ..< LEG_COUNT {
		foot, hit := spider_foot_target(sim, index)
		if !hit {
			center := body_center(&sim.player, sim.player.position)
			foot = center + rotate_yaw(LEG_RESTS[index], sim.player.yaw)
			foot.y = sim.player.position.y + LEG_PLANT_LIFT
		}
		sim.player.legs[index] = {
			foot          = foot,
			previous_foot = foot,
			swing_target  = foot,
			planted       = true,
		}
	}
}

// Advances the gait by one fixed step. One tetrapod group swings at a time:
// when four feet of a group drift past the trigger, they all lift together, and
// the other group stays planted. Planted feet stay in the world. An airborne
// spider folds its legs toward the body.
@(private)
spider_update_legs :: proc(sim: ^Simulation, time_step: f32) {
	player := &sim.player
	center := body_center(player, player.position)

	active_group := -1
	for _, index in player.legs {
		leg := &player.legs[index]
		leg.previous_foot = leg.foot

		if !player.grounded {
			leg.swinging = false
			leg.planted = false
			tuck := rotate_yaw(LEG_RESTS[index] * LEG_TUCK_SCALE, player.yaw)
			leg.foot = center + tuck + b3.Vec3{0.0, LEG_TUCK_LIFT, 0.0}
			continue
		}

		if !leg.swinging {
			continue
		}
		leg.swing_elapsed += time_step
		raw := clamp(leg.swing_elapsed / max(leg.duration, 0.001), 0.0, 1.0)
		eased := raw * raw * (3.0 - 2.0 * raw)
		leg.foot =
			leg.swing_from + (leg.swing_target - leg.swing_from) * eased +
			b3.Vec3{0.0, math.sin(raw * math.PI) * LEG_STEP_LIFT, 0.0}
		if raw >= 1.0 {
			leg.foot = leg.swing_target
			leg.swinging = false
			leg.planted = true
		} else {
			active_group = int(LEG_GROUP[index])
		}
	}
	if !player.grounded {
		return
	}

	// A leg wants to move when its planted foot has drifted past the trigger,
	// or when it is waiting to land after a jump. Both groups usually want to
	// move, so the groups take turns; picking the first in leg order would
	// starve the other group and drag its feet out of reach.
	wants: [LEG_COUNT]bool
	for leg, index in player.legs {
		if leg.swinging {
			continue
		}
		if !leg.planted {
			wants[index] = true
			continue
		}
		rest := rotate_yaw(LEG_RESTS[index], player.yaw)
		wanted := b3.Vec3{center.x + rest.x, 0.0, center.z + rest.z}
		drift := b3.Vec3{leg.foot.x - wanted.x, 0.0, leg.foot.z - wanted.z}
		wants[index] = b3.Length(drift) > LEG_STEP_TRIGGER
	}

	if active_group >= 0 {
		return
	}
	start_group := -1
	for offset in 0 ..< 2 {
		group := int((int(player.next_gait_group) + offset) % 2)
		wants_group := false
		for _, index in player.legs {
			if wants[index] && int(LEG_GROUP[index]) == group {
				wants_group = true
				break
			}
		}
		if wants_group {
			start_group = group
			break
		}
	}
	if start_group < 0 {
		return
	}
	player.next_gait_group = u8((start_group + 1) % 2)
	for leg, index in player.legs {
		if !wants[index] || int(LEG_GROUP[index]) != start_group {
			continue
		}
		foot, hit := spider_foot_target(sim, index)
		if !hit {
			continue
		}
		duration: f32 = leg.planted ? LEG_STEP_DURATION : LEG_LANDING_DURATION
		start_swing(&player.legs[index], leg.foot, foot, duration)
	}
}

spider_planted_count :: proc(player: ^Player) -> int {
	count := 0
	for leg in player.legs {
		if leg.planted {
			count += 1
		}
	}
	return count
}

// The palette is the spider's own. The body sits in the red family, which no
// arena surface uses, so the character never reads as a prop. The eyes and the
// abdomen markings are emissive, so the spider is legible in the unlit arena
// without a player light that would break the darkness rule.
SPIDER_CEPHALOTHORAX_COLOR :: [4]f32{0.30, 0.10, 0.13, 1.0}
SPIDER_ABDOMEN_COLOR :: [4]f32{0.24, 0.08, 0.11, 1.0}
SPIDER_LEG_COLOR :: [4]f32{0.20, 0.07, 0.09, 1.0}
SPIDER_KNEE_COLOR :: [4]f32{0.28, 0.10, 0.12, 1.0}
SPIDER_EYE_COLOR :: [4]f32{1.00, 0.62, 0.16, 1.0}
SPIDER_EYE_EMISSIVE :: f32(2.4)
SPIDER_MARK_COLOR :: [4]f32{0.90, 0.42, 0.10, 1.0}
SPIDER_MARK_EMISSIVE :: f32(0.55)

SPIDER_EYES := [4]b3.Vec3 {
	{-0.10, 0.10, -0.47},
	{0.10, 0.10, -0.47},
	{-0.19, 0.07, -0.44},
	{0.19, 0.07, -0.44},
}

// The marks sit above the abdomen shell, so the camera behind the spider still
// sees them. Two bars read as markings; a left and right pair read as eyes.
SPIDER_MARKS := [2]b3.Vec3 {
	{0.0, 0.245, 0.34},
	{0.0, 0.245, 0.46},
}

SPIDER_EMISSIVE_COUNT :: len(SPIDER_EYES) + len(SPIDER_MARKS)
SPIDER_BOX_COUNT :: 2 + SPIDER_EMISSIVE_COUNT + LEG_COUNT * 3

yaw_quaternion :: proc(yaw: f32) -> [4]f32 {
	half := yaw * 0.5
	return {0.0, math.sin(half), 0.0, math.cos(half)}
}
