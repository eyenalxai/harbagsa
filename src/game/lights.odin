#+vet explicit-allocators
#+vet !unused-procedures // the agent harness and tests call this API; the game binary does not
package game

import "core:math"

MAX_ACTIVE_LIGHTS :: 8

LIGHT_INTENSITY_MIN :: 0.2
LIGHT_INTENSITY_MAX :: 4.0
LIGHT_INTENSITY_STEP :: 0.2
LIGHT_RANGE_MIN :: 2.0
LIGHT_RANGE_MAX :: 20.0
LIGHT_RANGE_STEP :: 1.0

LIGHT_EMISSIVE_BASE :: 0.35
LIGHT_EMISSIVE_RATE :: 0.20

Light_Color :: enum {
	Warm,
	Cool,
	Red,
	Green,
	Blue,
}

LIGHT_COLOR_COUNT :: int(Light_Color.Blue) + 1

LIGHT_COLOR_NAMES := [LIGHT_COLOR_COUNT]string{"warm", "cool", "red", "green", "blue"}

LIGHT_COLOR_RGB := [LIGHT_COLOR_COUNT][3]f32 {
	{1.00, 0.78, 0.45},
	{0.55, 0.78, 1.00},
	{1.00, 0.30, 0.22},
	{0.40, 0.95, 0.45},
	{0.42, 0.60, 1.00},
}

// The placed object and the prefab share this type. `active` separates "this box
// is a lamp" from the tuned values, so a spawn that omits the light still gets
// the prefab defaults.
Light_Settings :: struct {
	active:    bool,
	color:     Light_Color,
	intensity: f32,
	range:     f32,
	emissive:  f32,
}

Light_Change :: enum {
	Color,
	Intensity_Down,
	Intensity_Up,
	Range_Down,
	Range_Up,
}

Active_Light :: struct {
	object_id: Object_Id,
	position:  [3]f32,
	color:     [3]f32,
	intensity: f32,
	range:     f32,
}

Active_Lights :: struct {
	count:  int,
	lights: [MAX_ACTIVE_LIGHTS]Active_Light,
}

light_emissive :: proc(intensity: f32) -> f32 {
	return LIGHT_EMISSIVE_BASE + LIGHT_EMISSIVE_RATE * intensity
}

light_settings :: proc(color: Light_Color, intensity, range: f32) -> Light_Settings {
	return {
		active = true,
		color = color,
		intensity = intensity,
		range = range,
		emissive = light_emissive(intensity),
	}
}

light_color_rgb :: proc(color: Light_Color) -> [3]f32 {
	return LIGHT_COLOR_RGB[color]
}

light_color4 :: proc(color: Light_Color) -> [4]f32 {
	rgb := light_color_rgb(color)
	return {rgb.x, rgb.y, rgb.z, 1.0}
}

light_color_name :: proc(color: Light_Color) -> string {
	return LIGHT_COLOR_NAMES[color]
}

light_color_parse :: proc(name: string) -> (Light_Color, bool) {
	for color in Light_Color {
		if LIGHT_COLOR_NAMES[color] == name {
			return color, true
		}
	}
	return .Warm, false
}

light_with_color :: proc(settings: Light_Settings, color: Light_Color) -> Light_Settings {
	result := settings
	result.color = color
	return result
}

light_with_intensity :: proc(settings: Light_Settings, intensity: f32) -> Light_Settings {
	result := settings
	result.intensity = clamp(light_round(intensity, 10.0), LIGHT_INTENSITY_MIN, LIGHT_INTENSITY_MAX)
	result.emissive = light_emissive(result.intensity)
	return result
}

light_with_range :: proc(settings: Light_Settings, range: f32) -> Light_Settings {
	result := settings
	result.range = clamp(math.round(range), LIGHT_RANGE_MIN, LIGHT_RANGE_MAX)
	return result
}

light_adjust :: proc(settings: Light_Settings, change: Light_Change) -> Light_Settings {
	switch change {
	case .Color:
		return light_with_color(settings, Light_Color((int(settings.color) + 1) % LIGHT_COLOR_COUNT))
	case .Intensity_Down:
		return light_with_intensity(settings, settings.intensity - LIGHT_INTENSITY_STEP)
	case .Intensity_Up:
		return light_with_intensity(settings, settings.intensity + LIGHT_INTENSITY_STEP)
	case .Range_Down:
		return light_with_range(settings, settings.range - LIGHT_RANGE_STEP)
	case .Range_Up:
		return light_with_range(settings, settings.range + LIGHT_RANGE_STEP)
	}
	return settings
}

// Nearest first, and the object id breaks a distance tie. The renderer draws the
// first eight, so the same camera and scene always upload the same lights.
simulation_collect_lights :: proc(sim: ^Simulation, camera_position: [3]f32) -> Active_Lights {
	candidates: [MAX_PLACED_OBJECTS]Active_Light
	distances: [MAX_PLACED_OBJECTS]f32
	count := 0
	for object in simulation_objects(sim) {
		if !object.light.active {
			continue
		}
		light := Active_Light {
			object_id = object.id,
			position  = object_box(object).center,
			color     = light_color_rgb(object.light.color),
			intensity = object.light.intensity,
			range     = object.light.range,
		}
		distance := squared_distance(light.position, camera_position)
		index := count
		for index > 0 && light_before(distance, light.object_id, distances[index - 1], candidates[index - 1].object_id) {
			candidates[index] = candidates[index - 1]
			distances[index] = distances[index - 1]
			index -= 1
		}
		candidates[index] = light
		distances[index] = distance
		count += 1
	}

	result: Active_Lights
	result.count = min(count, MAX_ACTIVE_LIGHTS)
	for index in 0 ..< result.count {
		result.lights[index] = candidates[index]
	}
	return result
}

simulation_lamp_count :: proc(sim: ^Simulation) -> int {
	count := 0
	for object in simulation_objects(sim) {
		if object.light.active {
			count += 1
		}
	}
	return count
}

simulation_active_light_count :: proc(sim: ^Simulation) -> int {
	return min(simulation_lamp_count(sim), MAX_ACTIVE_LIGHTS)
}

simulation_set_object_light :: proc(sim: ^Simulation, id: Object_Id, settings: Light_Settings) -> bool {
	index, ok := object_index_for_id(sim, id)
	if !ok {
		return false
	}
	object := &sim.objects[index]
	if !object.light.active {
		return false
	}
	object.light = settings
	object.color = light_color4(settings.color)
	return true
}

@(private)
light_before :: proc(distance: f32, id: Object_Id, other_distance: f32, other_id: Object_Id) -> bool {
	if distance == other_distance {
		return id < other_id
	}
	return distance < other_distance
}

@(private)
squared_distance :: proc(a, b: [3]f32) -> f32 {
	offset := a - b
	return offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
}

@(private)
light_round :: proc(value, scale: f32) -> f32 {
	return math.round(value * scale) / scale
}
