#+vet explicit-allocators
package game

import "core:c"
import "core:math"
import b3 "libs:box3d"

Headroom_Query :: struct {
	threshold: f32,
	blocked:   bool,
}

@(private)
headroom_overlap :: proc "c" (shape_id: b3.ShapeId, ctx: rawptr) -> bool {
	query := cast(^Headroom_Query)ctx
	aabb := b3.Shape_GetAABB(shape_id)
	if aabb.lowerBound.y >= query.threshold {
		query.blocked = true
		return false
	}
	return true
}

// Headroom is a ceiling check, not a full-capsule overlap. A step or a crate
// beside the feet touches the capsule but does not block a taller stance. A
// shape whose lower bound starts above the step height is a ceiling.
has_headroom :: proc(sim: ^Simulation, feet: b3.Vec3, stance: Stance) -> bool {
	height := stance_height(stance)
	points: [2]b3.Vec3
	points[0] = {0.0, PLAYER_RADIUS, 0.0}
	points[1] = {0.0, max(height - PLAYER_RADIUS, PLAYER_RADIUS), 0.0}

	proxy := b3.ShapeProxy {
		points = raw_data(points[:]),
		count = c.int(2),
		radius = PLAYER_RADIUS,
	}
	query := Headroom_Query {
		threshold = feet.y + HEADROOM_CEILING_MARGIN,
	}
	origin := feet + b3.Vec3{0.0, HEADROOM_PROBE_LIFT, 0.0}
	_ = b3.World_OverlapShape(
		sim.world_id,
		origin,
		proxy,
		b3.DefaultQueryFilter(),
		headroom_overlap,
		&query,
	)
	return !query.blocked
}

choose_stance :: proc(requested: Stance, standing_fits, crouching_fits: bool) -> Stance {
	switch requested {
	case .Prone:
		return .Prone
	case .Crouching:
		return crouching_fits ? .Crouching : .Prone
	case .Standing:
		if standing_fits {
			return .Standing
		}
		if crouching_fits {
			return .Crouching
		}
		return .Prone
	}
	return .Standing
}

stance_request :: proc(player: ^Player) -> Stance {
	if player.prone_engaged {
		return .Prone
	}
	if player.crouch_engaged {
		return .Crouching
	}
	return .Standing
}

engagement_step :: proc(
	mode: Input_Mode,
	engaged, other_engaged: bool,
	pressed, held: bool,
) -> (bool, bool) {
	next_engaged := engaged
	next_other := other_engaged
	if mode == .Hold {
		if pressed {
			next_other = false
		}
		next_engaged = held
	} else if pressed {
		next_engaged = !next_engaged
		if next_engaged {
			next_other = false
		}
	}
	return next_engaged, next_other
}

@(private)
update_engagement :: proc(engaged, other_engaged: ^bool, pressed, held: bool, mode: Input_Mode) {
	engaged^, other_engaged^ = engagement_step(
		mode,
		engaged^,
		other_engaged^,
		pressed,
		held,
	)
}

@(private)
update_stance_input :: proc(player: ^Player, input: Input_Snapshot) {
	if player.movement_state != .None {
		return
	}
	update_engagement(
		&player.crouch_engaged,
		&player.prone_engaged,
		input.crouch_pressed,
		input.crouch_held,
		CROUCH_INPUT_MODE,
	)
	update_engagement(
		&player.prone_engaged,
		&player.crouch_engaged,
		input.prone_pressed,
		input.prone_held,
		PRONE_INPUT_MODE,
	)
}

sprint_request_step :: proc(
	mode: Input_Mode,
	engaged, held, pressed: bool,
) -> (bool, bool) {
	if mode == .Hold {
		return engaged, held
	}
	next := engaged
	if pressed {
		next = !next
	}
	return next, next
}

@(private)
update_sprint_input :: proc(player: ^Player, input: Input_Snapshot) {
	if player.movement_state != .None {
		player.sprint_wanted = false
		return
	}

	engaged, requested := sprint_request_step(
		SPRINT_INPUT_MODE,
		player.sprint_toggled,
		input.sprint_held,
		input.sprint_pressed,
	)
	player.sprint_toggled = engaged
	player.sprint_wanted = requested
}

@(private)
resolve_stance :: proc(sim: ^Simulation, input: Input_Snapshot) {
	player := &sim.player
	switch player.movement_state {
	case .Diving, .Sliding_Dive:
		player.stance = .Prone
		player.gait = .Walk
		return
	case .Sliding_Crouch:
		player.stance = .Crouching
		player.gait = .Walk
		return
	case .Mantling:
		player.gait = .Walk
		return
	case .None:
	}

	requested := stance_request(player)
	standing_fits := has_headroom(sim, player.position, .Standing)
	crouching_fits := has_headroom(sim, player.position, .Crouching)
	sprint_active := false

	if player.sprint_wanted {
		if standing_fits {
			if requested != .Standing {
				player.crouch_engaged = false
				player.prone_engaged = false
			}
			requested = .Standing
			sprint_active = true
		} else if SPRINT_INPUT_MODE == .Toggle &&
		   input.sprint_pressed &&
		   player.sprint_toggled {
			player.sprint_toggled = false
			player.sprint_wanted = false
		}
	}

	chosen := choose_stance(requested, standing_fits, crouching_fits)
	if chosen != .Standing {
		sprint_active = false
	}
	player.stance = chosen
	player.gait = sprint_active ? .Sprint : .Walk
}

@(private)
update_eye_height :: proc(player: ^Player, time_step: f32) {
	target := stance_eye_height(player.stance)
	alpha := 1.0 - math.exp(-EYE_HEIGHT_SMOOTH_RATE * time_step)
	player.eye_height += (target - player.eye_height) * alpha
}
