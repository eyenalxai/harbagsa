#+vet explicit-allocators
package reference

import "core:math"
import "core:math/linalg"

// Mirrors src/renderer/shaders/sky.glsl. The sky is a background and a probe
// miss source, not a physical atmosphere. The disk is art-directed, so the
// reference must reproduce it rather than approximate it: a probe ray that
// escapes to the sky returns this value.

SKY_ZENITH :: [3]f32{0.10, 0.20, 0.42}
SKY_HORIZON :: [3]f32{0.52, 0.62, 0.74}
SKY_GROUND :: [3]f32{0.16, 0.17, 0.18}
SKY_SUN_COLOR :: [3]f32{1.0, 0.97, 0.90}
SKY_GLOW_COLOR :: [3]f32{1.0, 0.86, 0.66}

sky_gradient :: proc(direction: [3]f32) -> [3]f32 {
	up := clamp(direction.y, 0.0, 1.0)
	above := SKY_HORIZON + (SKY_ZENITH - SKY_HORIZON) * math.pow(up, 0.45)
	below := clamp(-direction.y * 4.0, 0.0, 1.0)
	return above + (SKY_GROUND - above) * below
}

sky_smoothstep :: proc(edge0, edge1, value: f32) -> f32 {
	t := clamp((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
}

sky_color :: proc(direction, sun_direction: [3]f32, sun_tangent: f32) -> [3]f32 {
	color := sky_gradient(direction)
	cosine := clamp(linalg.vector_dot(direction, sun_direction), -1.0, 1.0)
	angle := math.acos(cosine)
	disk := 1.0 - sky_smoothstep(sun_tangent * 0.85, sun_tangent * 1.15, angle)
	glow := math.pow(max(cosine, 0.0), 512.0) * 0.9 + math.pow(max(cosine, 0.0), 24.0) * 0.10
	return color + SKY_SUN_COLOR * (disk * 12.0) + SKY_GLOW_COLOR * glow
}
