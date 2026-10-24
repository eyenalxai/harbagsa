#+vet explicit-allocators
package harness

import "core:math"

import "src:game"

session_sun :: proc(session: ^Session, command: Sun_Command) {
	if command.clear {
		session.debug.sun_direction = game.DEFAULT_SUN_DIRECTION
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
		session.debug.sun_direction = game.light_direction_from_sun(
			game.sun_direction_from_angles(azimuth, elevation),
		)
	}
	if command.has_diameter {
		session.debug.sun_angular_diameter = math.to_radians(command.diameter)
	}
}
