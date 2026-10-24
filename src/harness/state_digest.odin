#+vet explicit-allocators
package harness

import "core:math"
import "core:mem"

import b3 "libs:box3d"
import "src:digest"
import "src:game"

state_digest :: proc(state: State, allocator: mem.Allocator) -> string {
	hash := digest.fnv()
	digest.write_i64(&hash, i64(state.frame))
	digest.write_f32(&hash, state.player.position.x)
	digest.write_f32(&hash, state.player.position.y)
	digest.write_f32(&hash, state.player.position.z)
	digest.write_f32(&hash, state.player.eye.x)
	digest.write_f32(&hash, state.player.eye.y)
	digest.write_f32(&hash, state.player.eye.z)
	digest.write_f32(&hash, state.player.velocity.x)
	digest.write_f32(&hash, state.player.velocity.y)
	digest.write_f32(&hash, state.player.velocity.z)
	digest.write_f32(&hash, state.player.yaw)
	digest.write_f32(&hash, state.player.pitch)
	digest.write_bool(&hash, state.player.grounded)
	digest.write_string(&hash, state.settings.window_mode)
	digest.write_string(&hash, state.settings.display)
	digest.write_i64(&hash, i64(state.settings.display_index))
	digest.write_string(&hash, state.settings.resolution)
	digest.write_string(&hash, state.settings.window_resolution)
	digest.write_string(&hash, state.settings.sprint_mode)
	digest.write_string(&hash, state.settings.crouch_mode)
	digest.write_string(&hash, state.settings.prone_mode)
	digest.write_f32(&hash, state.settings.type_weight)
	digest.write_bool(&hash, state.menu.open)
	digest.write_i64(&hash, i64(state.menu.selected))
	digest.write_i64(&hash, i64(len(state.crates)))
	for crate in state.crates {
		digest.write_f32(&hash, crate.position.x)
		digest.write_f32(&hash, crate.position.y)
		digest.write_f32(&hash, crate.position.z)
		digest.write_f32(&hash, crate.rotation.x)
		digest.write_f32(&hash, crate.rotation.y)
		digest.write_f32(&hash, crate.rotation.z)
		digest.write_f32(&hash, crate.rotation.w)
	}
	return digest.hex(hash, allocator)
}

@(private)
vec_state :: proc(value: b3.Vec3) -> Vec_State {
	return {x = value.x, y = value.y, z = value.z}
}

@(private)
sun_state :: proc(debug: ^game.Debug_Mode) -> Sun_State {
	azimuth, elevation := game.debug_mode_sun_angles(debug)
	return {
		azimuth = math.to_degrees(azimuth),
		elevation = math.to_degrees(elevation),
		angular_diameter = math.to_degrees(debug.sun_angular_diameter),
	}
}

@(private)
menu_selected_blocked :: proc(menu: ^game.Menu_State) -> bool {
	if !menu.open {
		return false
	}
	row := game.MENU_ITEM_ROWS[int(menu.selected)]
	return menu.rows[row].blocked
}
