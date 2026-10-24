#+vet explicit-allocators
#+vet !unused-procedures // the renderer tests read the uploaded light buffer
package renderer

import "core:log"

import "src:geometry"

MAX_POINT_LIGHTS :: 8

// The shader reads this as two vec4s: position.xyz + intensity, color.rgb + range.
Light :: struct {
	position:  [3]f32,
	intensity: f32,
	color:     [3]f32,
	range:     f32,
}

#assert(size_of(Light) == 32)

LAMP_INSTANCE_MASK :: 0x01
BOX_INSTANCE_MASK :: 0xFF

// A lamp must not block its own point light, so it gets a mask the point shadow
// ray does not test. The sun ray uses every mask bit and still sees the lamp.
box_instance_mask :: proc(box: geometry.Box) -> u32 {
	return box.emissive > 0 ? LAMP_INSTANCE_MASK : BOX_INSTANCE_MASK
}

SYNTHETIC_LIGHT_COLOR :: [3]f32{1.0, 0.82, 0.62}
SYNTHETIC_LIGHT_INTENSITY :: 3.0
SYNTHETIC_LIGHT_RANGE :: 8.0

SYNTHETIC_LIGHTS := [MAX_POINT_LIGHTS]Light {
	{{-3, 2.6, 4}, SYNTHETIC_LIGHT_INTENSITY, SYNTHETIC_LIGHT_COLOR, SYNTHETIC_LIGHT_RANGE},
	{{0, 2.6, 4}, SYNTHETIC_LIGHT_INTENSITY, SYNTHETIC_LIGHT_COLOR, SYNTHETIC_LIGHT_RANGE},
	{{3, 2.6, 4}, SYNTHETIC_LIGHT_INTENSITY, SYNTHETIC_LIGHT_COLOR, SYNTHETIC_LIGHT_RANGE},
	{{-3, 2.6, 0}, SYNTHETIC_LIGHT_INTENSITY, SYNTHETIC_LIGHT_COLOR, SYNTHETIC_LIGHT_RANGE},
	{{3, 2.6, 0}, SYNTHETIC_LIGHT_INTENSITY, SYNTHETIC_LIGHT_COLOR, SYNTHETIC_LIGHT_RANGE},
	{{-3, 2.6, -4}, SYNTHETIC_LIGHT_INTENSITY, SYNTHETIC_LIGHT_COLOR, SYNTHETIC_LIGHT_RANGE},
	{{0, 2.6, -4}, SYNTHETIC_LIGHT_INTENSITY, SYNTHETIC_LIGHT_COLOR, SYNTHETIC_LIGHT_RANGE},
	{{3, 2.6, -4}, SYNTHETIC_LIGHT_INTENSITY, SYNTHETIC_LIGHT_COLOR, SYNTHETIC_LIGHT_RANGE},
}

// The debug override replaces the frame's lights so a perf run can measure a
// full light budget before the game has lamp prefabs.
frame_lights :: proc(r: ^Renderer, lights: []Light) -> []Light {
	if r.taa.debug.active && r.taa.debug.synthetic_lights > 0 {
		return synthetic_lights(r.taa.debug.synthetic_lights)
	}
	return lights
}

synthetic_lights :: proc(count: int) -> []Light {
	limit := min(count, MAX_POINT_LIGHTS)
	return SYNTHETIC_LIGHTS[:limit]
}

write_light_data :: proc(r: ^Renderer, lights: []Light) -> bool {
	data := cast([^]Light)r.scene.light_mapped[r.frame_index]
	if data == nil {
		log.error("renderer: light storage buffer is not mapped")
		return false
	}
	count := min(len(lights), MAX_POINT_LIGHTS)
	for index in 0 ..< count {
		data[index] = lights[index]
	}
	r.light_count = count
	return true
}

// The renderer tests read the buffer back to prove the upload matches the frame.
lights_uploaded :: proc(r: ^Renderer) -> []Light {
	data := cast([^]Light)r.scene.light_mapped[r.frame_index]
	if data == nil {
		return nil
	}
	return data[:r.light_count]
}
