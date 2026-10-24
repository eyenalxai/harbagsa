#+vet explicit-allocators
package harness

import "core:fmt"

@(private)
debug_field :: proc(debug: Debug_State, path: string) -> (Check_Value, string) {
	head, tail, has_tail := split_field(path)
	switch head {
	case "active":
		return {kind = .Bool, boolean = debug.active}, ""
	case "selection":
		return {kind = .String, text = debug.selection}, ""
	case "selected_id":
		return {kind = .Number, number = f64(debug.selected_id)}, ""
	case "palette":
		if !has_tail {
			return {}, "debug.palette needs a field"
		}
		return palette_field(debug.palette, tail)
	case "placement":
		if !has_tail {
			return {}, "debug.placement needs a field"
		}
		return placement_field(debug.placement, tail)
	case "sun":
		if !has_tail {
			return {}, "debug.sun needs a field"
		}
		return sun_field(debug.sun, tail)
	case "inspector":
		if !has_tail {
			return {}, "debug.inspector needs a field"
		}
		return inspector_field(debug.inspector, tail)
	case "history":
		if !has_tail {
			return {}, "debug.history needs a field"
		}
		return history_field(debug.history, tail)
	case "lights":
		if !has_tail {
			return {}, "debug.lights needs a field"
		}
		return light_budget_field(debug.lights, tail)
	}
	return {}, fmt.aprintf("unknown debug field %q", path, allocator = context.allocator)
}

@(private)
palette_field :: proc(palette: Palette_State, path: string) -> (Check_Value, string) {
	switch path {
	case "open":
		return {kind = .Bool, boolean = palette.open}, ""
	case "selected":
		return {kind = .Number, number = f64(palette.selected)}, ""
	case "body":
		return {kind = .String, text = palette.body}, ""
	}
	return {}, fmt.aprintf("unknown debug.palette field %q", path, allocator = context.allocator)
}

@(private)
placement_field :: proc(placement: Placement_State, path: string) -> (Check_Value, string) {
	head, tail, has_tail := split_field(path)
	switch head {
	case "armed":
		return {kind = .Bool, boolean = placement.armed}, ""
	case "prefab":
		return {kind = .String, text = placement.prefab}, ""
	case "height":
		return {kind = .Number, number = f64(placement.height)}, ""
	case "yaw":
		return {kind = .Number, number = f64(placement.yaw)}, ""
	case "snap":
		return {kind = .Bool, boolean = placement.snap}, ""
	case "position":
		if !has_tail {
			return {}, "debug.placement.position needs an axis"
		}
		return vec_field(placement.position, tail)
	case "light":
		if !has_tail {
			return {}, "debug.placement.light needs a field"
		}
		return light_field(placement.light, tail)
	}
	return {}, fmt.aprintf("unknown debug.placement field %q", path, allocator = context.allocator)
}

@(private)
sun_field :: proc(sun: Sun_State, path: string) -> (Check_Value, string) {
	head, tail, has_tail := split_field(path)
	switch head {
	case "active":
		return {kind = .Bool, boolean = sun.active}, ""
	case "azimuth":
		return {kind = .Number, number = f64(sun.azimuth)}, ""
	case "elevation":
		return {kind = .Number, number = f64(sun.elevation)}, ""
	case "angular_diameter":
		return {kind = .Number, number = f64(sun.angular_diameter)}, ""
	case "position":
		if !has_tail {
			return {}, "debug.sun.position needs an axis"
		}
		return vec_field(sun.position, tail)
	}
	return {}, fmt.aprintf("unknown debug.sun field %q", path, allocator = context.allocator)
}

@(private)
inspector_field :: proc(inspector: Inspector_State, path: string) -> (Check_Value, string) {
	head, tail, has_tail := split_field(path)
	switch head {
	case "prefab":
		return {kind = .String, text = inspector.prefab}, ""
	case "body":
		return {kind = .String, text = inspector.body}, ""
	case "yaw":
		return {kind = .Number, number = f64(inspector.yaw)}, ""
	case "snap":
		return {kind = .Bool, boolean = inspector.snap}, ""
	case "size":
		if !has_tail {
			return {}, "debug.inspector.size needs an axis"
		}
		return vec_field(inspector.size, tail)
	case "position":
		if !has_tail {
			return {}, "debug.inspector.position needs an axis"
		}
		return vec_field(inspector.position, tail)
	case "light":
		if !has_tail {
			return {}, "debug.inspector.light needs a field"
		}
		return light_field(inspector.light, tail)
	}
	return {}, fmt.aprintf("unknown debug.inspector field %q", path, allocator = context.allocator)
}

@(private)
light_field :: proc(light: Light_State, path: string) -> (Check_Value, string) {
	switch path {
	case "active":
		return {kind = .Bool, boolean = light.active}, ""
	case "color":
		return {kind = .String, text = light.color}, ""
	case "intensity":
		return {kind = .Number, number = f64(light.intensity)}, ""
	case "range":
		return {kind = .Number, number = f64(light.range)}, ""
	}
	return {}, fmt.aprintf("unknown light field %q", path, allocator = context.allocator)
}

@(private)
light_budget_field :: proc(lights: Light_Budget_State, path: string) -> (Check_Value, string) {
	switch path {
	case "active":
		return {kind = .Number, number = f64(lights.active)}, ""
	case "lamps":
		return {kind = .Number, number = f64(lights.lamps)}, ""
	}
	return {}, fmt.aprintf("unknown debug.lights field %q", path, allocator = context.allocator)
}

@(private)
history_field :: proc(history: History_State, path: string) -> (Check_Value, string) {
	switch path {
	case "depth":
		return {kind = .Number, number = f64(history.depth)}, ""
	case "redo":
		return {kind = .Number, number = f64(history.redo)}, ""
	}
	return {}, fmt.aprintf("unknown debug.history field %q", path, allocator = context.allocator)
}
