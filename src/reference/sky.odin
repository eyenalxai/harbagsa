#+vet explicit-allocators
package reference

import "core:math"

// Mirrors src/renderer/shaders/sky.glsl. The sky is a background and a probe
// miss source, not a physical atmosphere. A probe ray that escapes to the sky
// returns this value.

SKY_ZENITH :: [3]f32{0.10, 0.20, 0.42}
SKY_HORIZON :: [3]f32{0.52, 0.62, 0.74}
SKY_GROUND :: [3]f32{0.16, 0.17, 0.18}

sky_gradient :: proc(direction: [3]f32) -> [3]f32 {
	up := clamp(direction.y, 0.0, 1.0)
	above := SKY_HORIZON + (SKY_ZENITH - SKY_HORIZON) * math.pow(up, 0.45)
	below := clamp(-direction.y * 4.0, 0.0, 1.0)
	return above + (SKY_GROUND - above) * below
}
