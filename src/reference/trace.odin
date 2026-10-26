#+vet explicit-allocators
package reference

import "core:math"
import "core:math/linalg"
import "core:mem"

// The estimator traces cosine-weighted diffuse paths from a fixed grid of
// pixel centres. `bounces` counts the diffuse bounces after the camera hit. One
// bounce matches the probe update; more bounces quantify the missing transport.
//
// Scale: a vertex returns `emission + albedo * (direct + mean_cos(next))`. The
// camera-hit value is the sRGB-independent scene colour the lit pass writes to
// the `scene_color` target. `mean_cos(next)` is the cosine-weighted mean
// radiance, which is exactly what the gather's `2 pi / pi` pair estimates from
// the probe atlas. The comparison therefore needs no fudge factor.

Settings :: struct {
	samples:     int `json:"samples"`,
	bounces:     int `json:"bounces"`,
	stride:      int `json:"stride"`,
	sun_samples: int `json:"sun_samples"`,
}

DEFAULT_SAMPLES :: 48
DEFAULT_BOUNCES :: 3
DEFAULT_STRIDE :: 16
DEFAULT_SUN_SAMPLES :: 16

MAX_BOUNCES :: 8

Sample :: struct {
	x:        int,
	y:        int,
	sky:      bool,
	edge:     bool,
	box:      int,
	distance: f32,
	albedo:   [3]f32,
	emission: [3]f32,
	direct:   [3]f32,
	indirect: [3]f32,
	radiance: [3]f32,
}

Grid :: struct {
	width:        int,
	height:       int,
	stride:       int,
	frame_width:  u32,
	frame_height: u32,
	samples:      []Sample,
}

Grid_Destroy :: proc(grid: ^Grid, allocator: mem.Allocator) {
	delete(grid.samples, allocator)
	grid^ = {}
}

// A 64-bit LCG whose high bits drive the samples. The seed names the pixel and
// the path index, so a run repeats exactly.
Rng :: struct {
	state: u64,
}

rng_seed :: proc(pixel, path: int) -> Rng {
	state := u64(u32(pixel)) * 0x9E3779B97F4A7C15 + u64(u32(path)) + 0x853C49E6748FEA9B
	return {state = state | 1}
}

rng_next :: proc(rng: ^Rng) -> f32 {
	rng.state = rng.state * 6364136223846793005 + 1442695040888963407
	return f32(rng.state >> 40) * (1.0 / 16777216.0)
}

// Duff et al., "Building an Orthonormal Basis, Revisited". The branchless form
// stays finite when the normal points along -Z.
orthonormal_basis :: proc(normal: [3]f32) -> (tangent, bitangent: [3]f32) {
	sign: f32 = 1.0 if normal.z >= 0.0 else -1.0
	a := -1.0 / (sign + normal.z)
	b := normal.x * normal.y * a
	tangent = {1.0 + sign * normal.x * normal.x * a, sign * b, -sign * normal.x}
	bitangent = {b, sign + normal.y * normal.y * a, -normal.y}
	return
}

cosine_hemisphere :: proc(normal: [3]f32, u1, u2: f32) -> [3]f32 {
	tangent, bitangent := orthonormal_basis(normal)
	radius := math.sqrt(u1)
	angle := 2.0 * math.PI * u2
	local := tangent * (radius * math.cos(angle)) + bitangent * (radius * math.sin(angle))
	return linalg.vector_normalize0(local + normal * math.sqrt(max(0.0, 1.0 - u1)))
}

vogel_disk :: proc(index, count: int, phase: f32) -> [2]f32 {
	radius := math.sqrt((f32(index) + 0.5) / f32(count))
	angle := f32(index) * 2.39996323 + phase
	return radius * [2]f32{math.cos(angle), math.sin(angle)}
}

// Mirrors sun_direction() in box.frag with a zero phase. The lit pass rotates
// the pattern per pixel and TAA averages it; the reference takes the fixed
// phase, which differs only inside a penumbra.
sun_sample_direction :: proc(to_light: [3]f32, tangent: f32, index, count: int) -> [3]f32 {
	up: [3]f32 = {0, 1, 0} if abs(to_light.y) < 0.99 else {1, 0, 0}
	side := linalg.vector_normalize0(linalg.vector_cross3(up, to_light))
	upward := linalg.vector_cross3(to_light, side)
	disk := vogel_disk(index, count, 0.0) * tangent
	return linalg.vector_normalize0(to_light + side * disk.x + upward * disk.y)
}

// Direct irradiance at a vertex, in the lit pass scale: the sun term is
// `SUN_COLOR * cos` and the point term is the same falloff the lit pass uses.
// The sun uses the disk set at the camera hit and one centre ray after a
// bounce, which is what probe_ray.comp traces.
direct_irradiance :: proc(
	scene: Scene,
	position, normal: [3]f32,
	sun_samples: int,
) -> [3]f32 {
	origin := position + normal * 0.002
	sum := [3]f32{}
	to_light := scene.sun_direction
	tangent := math.tan(scene.sun_angle * 0.5)
	if sun_samples <= 1 {
		cosine := max(linalg.vector_dot(normal, to_light), 0.0)
		if cosine > 0.0 && !occluded(scene, origin, to_light, false, RAY_FAR) {
			sum += SUN_COLOR * cosine
		}
	} else {
		scale := SUN_COLOR * (1.0 / f32(sun_samples))
		for index in 0 ..< sun_samples {
			direction := sun_sample_direction(to_light, tangent, index, sun_samples)
			cosine := max(linalg.vector_dot(normal, direction), 0.0)
			if cosine > 0.0 && !occluded(scene, origin, direction, false, RAY_FAR) {
				sum += scale * cosine
			}
		}
	}

	for light in scene.lights {
		offset := light.position - position
		distance := linalg.vector_length(offset)
		if distance <= 0.0 || distance >= light.range {
			continue
		}
		direction := offset * (1.0 / distance)
		diffuse := max(linalg.vector_dot(normal, direction), 0.0)
		if diffuse <= 0.0 {
			continue
		}
		reach := distance / light.range
		falloff := 1.0 - reach * reach
		falloff *= falloff
		shadow_distance := max(distance - 0.001, 0.0)
		if occluded(scene, origin, direction, true, shadow_distance) {
			continue
		}
		sum += light.color * (light.intensity * diffuse * falloff)
	}
	return sum
}

Trace :: struct {
	direct:   [3]f32,
	indirect: [3]f32,
	radiance: [3]f32,
}

trace_path :: proc(
	scene: Scene,
	hit: Hit,
	depth: int,
	settings: Settings,
	rng: ^Rng,
) -> Trace {
	sun_samples := settings.sun_samples if depth == 0 else 1
	direct := hit.albedo * direct_irradiance(scene, hit.position, hit.normal, sun_samples)
	indirect := [3]f32{}
	if depth < settings.bounces {
		direction := cosine_hemisphere(
			hit.normal,
			rng_next(rng),
			rng_next(rng),
		)
		next := intersect(scene, hit.position + hit.normal * RAY_BIAS, direction)
		radiance: [3]f32
		if next.hit {
			radiance = trace_path(scene, next, depth + 1, settings, rng).radiance
		} else {
			tangent := math.tan(scene.sun_angle * 0.5)
			radiance = sky_color(direction, scene.sun_direction, tangent)
		}
		indirect = hit.albedo * radiance
	}
	return {
		direct = direct,
		indirect = indirect,
		radiance = hit.emission + direct + indirect,
	}
}

// A pixel near a geometry edge has a first hit the rasterizer and the CPU ray
// can disagree on. Four half-pixel probes reject it, so the comparison never
// pairs a surface with a different one.
sample_edge :: proc(scene: Scene, camera: Camera, width, height: u32, x, y: int, hit: Hit) -> bool {
	offsets := [4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
	for offset in offsets {
		probe_x := clamp(x + offset.x, 0, int(width) - 1)
		probe_y := clamp(y + offset.y, 0, int(height) - 1)
		direction := camera_ray(camera, width, height, probe_x, probe_y)
		probe := intersect(scene, camera.position, direction)
		if !probe.hit || probe.box != hit.box {
			return true
		}
		if abs(probe.distance - hit.distance) > max(hit.distance * 0.02, 0.002) {
			return true
		}
	}
	return false
}

estimate :: proc(
	scene: Scene,
	settings: Settings,
	frame_width, frame_height: u32,
	allocator: mem.Allocator,
) -> Grid {
	stride := max(settings.stride, 1)
	samples := max(settings.samples, 1)
	resolved := settings
	resolved.bounces = clamp(settings.bounces, 1, MAX_BOUNCES)
	grid := Grid {
		width = int((frame_width + u32(stride) - 1) / u32(stride)),
		height = int((frame_height + u32(stride) - 1) / u32(stride)),
		stride = stride,
		frame_width = frame_width,
		frame_height = frame_height,
	}
	grid.samples = make([]Sample, grid.width * grid.height, allocator)
	for gy in 0 ..< grid.height {
		for gx in 0 ..< grid.width {
			x := min(gx * stride + stride / 2, int(frame_width) - 1)
			y := min(gy * stride + stride / 2, int(frame_height) - 1)
			sample := Sample{x = x, y = y}
			direction := camera_ray(scene.camera, frame_width, frame_height, x, y)
			hit := intersect(scene, scene.camera.position, direction)
			if !hit.hit {
				sample.sky = true
				sample.radiance = sky_color(
					direction,
					scene.sun_direction,
					math.tan(scene.sun_angle * 0.5),
				)
				grid.samples[gy * grid.width + gx] = sample
				continue
			}
			// An edge sample stays out of the metrics but still feeds the
			// headless target, so the image has no holes.
			sample.edge = sample_edge(scene, scene.camera, frame_width, frame_height, x, y, hit)
			sample.box = hit.box
			sample.distance = hit.distance
			sample.albedo = hit.albedo
			sample.emission = hit.emission
			pixel := gy * grid.width + gx
			total := Trace{}
			for path in 0 ..< samples {
				rng := rng_seed(pixel, path)
				value := trace_path(scene, hit, 0, resolved, &rng)
				total.direct += value.direct
				total.indirect += value.indirect
				total.radiance += value.radiance
			}
			scale := 1.0 / f32(samples)
			sample.direct = total.direct * scale
			sample.indirect = total.indirect * scale
			sample.radiance = total.radiance * scale
			grid.samples[pixel] = sample
		}
	}
	return grid
}

// The reference image the run writes as a headless target: linear scene
// radiance at the sampled grid, sRGB encoded for viewing.
grid_pixels :: proc(grid: Grid, allocator: mem.Allocator) -> []u8 {
	pixels := make([]u8, grid.width * grid.height * 4, allocator)
	for sample, index in grid.samples {
		base := index * 4
		for channel in 0 ..< 3 {
			pixels[base + channel] = linear_to_srgb8(sample.radiance[channel])
		}
		pixels[base + 3] = 255
	}
	return pixels
}

linear_to_srgb8 :: proc(value: f32) -> u8 {
	linear := clamp(value, 0.0, 1.0)
	encoded := linear * 12.92 if linear <= 0.0031308 else 1.055 * math.pow(linear, 1.0 / 2.4) - 0.055
	return u8(clamp(encoded * 255.0 + 0.5, 0.0, 255.0))
}
