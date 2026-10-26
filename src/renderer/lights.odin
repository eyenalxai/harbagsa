#+vet explicit-allocators
#+vet !unused-procedures // the renderer tests read the uploaded light buffer
package renderer

import "core:log"
import "core:math"

import "src:geometry"

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
// ray does not test. The occlusion rays use every mask bit and still see the
// lamp.
box_instance_mask :: proc(box: geometry.Box) -> u32 {
	return box.emissive > 0 ? LAMP_INSTANCE_MASK : BOX_INSTANCE_MASK
}

SYNTHETIC_LIGHT_COLOR :: [3]f32{1.0, 0.82, 0.62}
SYNTHETIC_LIGHT_INTENSITY :: 3.0
SYNTHETIC_LIGHT_RANGE :: 8.0

// The debug override replaces the frame's lights so a perf run can measure a
// full light budget before the game has lamp prefabs. The positions form a
// square grid, so the count has no upper bound.
frame_lights :: proc(r: ^Renderer, lights: []Light) -> []Light {
	if r.taa.debug.active && r.taa.debug.synthetic_lights > 0 {
		return synthetic_lights(r, r.taa.debug.synthetic_lights)
	}
	return lights
}

synthetic_lights :: proc(r: ^Renderer, count: int) -> []Light {
	if count <= 0 {
		return nil
	}
	resize(&r.synthetic_lights, count)
	side := int(math.ceil(math.sqrt(f32(count))))
	for index in 0 ..< count {
		x := f32(index % side) - f32(side-1) * 0.5
		z := f32(index / side) - f32(side-1) * 0.5
		r.synthetic_lights[index] = {
			position  = {x * 2.0, 2.6, z * 2.0},
			intensity = SYNTHETIC_LIGHT_INTENSITY,
			color     = SYNTHETIC_LIGHT_COLOR,
			range     = SYNTHETIC_LIGHT_RANGE,
		}
	}
	return r.synthetic_lights[:]
}

write_light_data :: proc(r: ^Renderer, lights: []Light) -> bool {
	data := cast([^]Light)r.scene.light_mapped[r.frame_index]
	if data == nil {
		log.error("renderer: light storage buffer is not mapped")
		return false
	}
	if len(lights) > r.scene.light_capacity {
		log.errorf(
			"renderer: %d lights exceed the %d-slot light buffer",
			len(lights),
			r.scene.light_capacity,
		)
		return false
	}
	for light, index in lights {
		data[index] = light
	}
	r.light_count = len(lights)
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
