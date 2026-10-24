#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:math"

import "src:renderer"

// The command describes the sun in the sky, not the light direction the
// renderer consumes: azimuth from +z toward +x, and elevation above the
// horizon. Diameter is the angle the sun disk subtends.
@(private)
parse_sun :: proc(object: json.Object) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "azimuth", "elevation", "diameter"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Sun}
	if value, has := json_get(object, "azimuth"); has {
		azimuth, ok := json_number(value)
		if !ok {
			return {}, format_error("%s", "'azimuth' must be a number")
		}
		command.sun.azimuth = f32(azimuth)
		command.sun.has_azimuth = true
	}
	if value, has := json_get(object, "elevation"); has {
		elevation, ok := json_number(value)
		if !ok || elevation < -90 || elevation > 90 {
			return {}, format_error("%s", "'elevation' must be a number in [-90, 90]")
		}
		command.sun.elevation = f32(elevation)
		command.sun.has_elevation = true
	}
	if value, has := json_get(object, "diameter"); has {
		limit := math.to_degrees(renderer.SUN_ANGULAR_DIAMETER_LIMIT)
		diameter, ok := json_number(value)
		if !ok || diameter <= 0 || diameter >= f64(limit) {
			return {}, format_error("'diameter' must be a number in (0, %v)", limit)
		}
		command.sun.diameter = f32(diameter)
		command.sun.has_diameter = true
	}
	if !command.sun.has_azimuth && !command.sun.has_elevation && !command.sun.has_diameter {
		return {}, format_error("%s", "sun needs 'azimuth', 'elevation' or 'diameter'")
	}
	return command, ""
}
