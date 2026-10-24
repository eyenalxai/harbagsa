#+vet explicit-allocators
package harness

import "core:math"

import "src:game"

// The command names the sun in the sky; the debug mode stores a dome position.
session_sun :: proc(session: ^Session, command: Sun_Command) {
	if command.clear {
		game.debug_sun_reset(&session.debug)
		session.debug.sun_angular_diameter = game.SUN_ANGULAR_DIAMETER
		return
	}
	azimuth, elevation := game.debug_mode_sun_angles(&session.debug)
	if command.has_azimuth {
		azimuth = math.to_radians(command.azimuth)
	}
	if command.has_elevation {
		elevation = math.to_radians(command.elevation)
	}
	if command.has_azimuth || command.has_elevation {
		direction := game.sun_direction_from_angles(azimuth, elevation)
		session.debug.sun.position = direction * f32(game.SUN_DOME_RADIUS)
	}
	if command.has_diameter {
		session.debug.sun_angular_diameter = math.to_radians(command.diameter)
	}
}
