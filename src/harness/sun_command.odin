#+vet explicit-allocators
package harness

import "core:encoding/json"
import "core:mem"
import "core:math"

import "src:renderer"

// The command describes the sun in the sky, not the light direction the
// renderer consumes: azimuth from +z toward +x, and elevation above the
// horizon. Every angle is in degrees; the session converts to radians.
@(private)
parse_sun :: proc(object: json.Object, _allocator: mem.Allocator) -> (Command, string) {
	if key, unknown := json_unknown_key(object, {"cmd", "azimuth_deg", "elevation_deg", "diameter_deg", "clear"}); unknown {
		return {}, format_error("unknown key %q", key)
	}
	command := Command{kind = .Sun}
	if field_error := json_bool(object, "clear", &command.sun.clear); field_error != "" {
		return {}, field_error
	}
	if value, has := json_get(object, "azimuth_deg"); has {
		azimuth, ok := json_number(value)
		if !ok {
			return {}, format_error("%s", "'azimuth_deg' must be a number")
		}
		command.sun.azimuth_deg = f32(azimuth)
		command.sun.has_azimuth = true
	}
	if value, has := json_get(object, "elevation_deg"); has {
		elevation, ok := json_number(value)
		if !ok || elevation < -90 || elevation > 90 {
			return {}, format_error("%s", "'elevation_deg' must be a number in [-90, 90]")
		}
		command.sun.elevation_deg = f32(elevation)
		command.sun.has_elevation = true
	}
	if value, has := json_get(object, "diameter_deg"); has {
		limit := math.to_degrees(renderer.SUN_ANGULAR_DIAMETER_LIMIT)
		diameter, ok := json_number(value)
		if !ok || diameter <= 0 || diameter >= f64(limit) {
			return {}, format_error("'diameter_deg' must be a number in (0, %v)", limit)
		}
		command.sun.diameter_deg = f32(diameter)
		command.sun.has_diameter = true
	}
	if command.sun.clear {
		if command.sun.has_azimuth || command.sun.has_elevation || command.sun.has_diameter {
			return {}, format_error("%s", "sun 'clear' cannot be combined with another field")
		}
		return command, ""
	}
	if !command.sun.has_azimuth && !command.sun.has_elevation && !command.sun.has_diameter {
		return {}, format_error("%s", "sun needs 'azimuth_deg', 'elevation_deg', 'diameter_deg', or 'clear'")
	}
	return command, ""
}
