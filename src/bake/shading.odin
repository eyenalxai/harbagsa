#+vet explicit-allocators
#+vet !unused-procedures // the lightmap and probe bakes share this
package bake

import "core:math"

import "src:geometry"

GOLDEN_ANGLE :: 2.39996322972865332
TWO_PI :: 6.28318530717958648

radical_inverse_base2 :: #force_inline proc(index: u32) -> f64 #no_bounds_check {
	bits := index
	result: u32
	for _ in 0 ..< 32 {
		result = (result << 1) | (bits & 1)
		bits >>= 1
	}
	return f64(result) * (1.0 / 4294967296.0)
}

cosine_hemisphere :: proc(normal: DVec3, index, count: int, rotation: [2]f64) -> DVec3 #no_bounds_check {
	u1 := math.mod((f64(index) + 0.5) / f64(count) + rotation.x, 1.0)
	u2 := math.mod(radical_inverse_base2(u32(index)) + rotation.y, 1.0)
	radius := math.sqrt(u1)
	angle := TWO_PI * u2
	tangent, bitangent := tangent_frame(normal)
	local_x := radius * math.cos(angle)
	local_y := radius * math.sin(angle)
	local_z := math.sqrt(max(0.0, 1.0 - u1))
	return dv_normalize(dv_add(
		dv_add(dv_mul(tangent, local_x), dv_mul(bitangent, local_y)),
		dv_mul(normal, local_z),
	))
}

tangent_frame :: proc(normal: DVec3) -> (tangent, bitangent: DVec3) {
	up := DVec3{0, 1, 0}
	if math.abs(normal.y) >= 0.999 {
		up = {1, 0, 0}
	}
	tangent = dv_normalize(dv_cross(up, normal))
	bitangent = dv_cross(normal, tangent)
	return
}

shade_hit :: proc(static: Static, bvh: ^Bvh, ray: Ray, hit: Hit) -> (radiance: [3]f64, shadows: u64) #no_bounds_check {
	box := static.boxes[hit.box].box
	albedo := DVec3{f64(box.color.x), f64(box.color.y), f64(box.color.z)}
	point := dv_add(ray.origin, dv_mul(ray.direction, hit.t))
	radiance = dv_mul(albedo, f64(box.emissive))
	for light in static.lights {
		offset := dv_sub(DVec3{f64(light.position.x), f64(light.position.y), f64(light.position.z)}, point)
		distance := dv_length(offset)
		reach := f64(light.range)
		if distance <= 0 || distance >= reach {
			continue
		}
		direction := dv_mul(offset, 1.0 / distance)
		diffuse := dv_dot(hit.normal, direction)
		if diffuse <= 0 {
			continue
		}
		falloff := 1.0 - (distance / reach) * (distance / reach)
		falloff *= falloff
		shadow_origin := dv_add(point, dv_mul(hit.normal, RAY_ORIGIN_BIAS))
		shadow_distance := max(distance - SHADOW_END_BIAS, 0.0)
		shadows += 1
		shadow_ray := ray_make(shadow_origin, direction)
		if shadow_occluded(bvh, shadow_ray, RAY_TMIN, shadow_distance) {
			continue
		}
		scale := f64(light.intensity) * diffuse * falloff
		color := DVec3{f64(light.color.x), f64(light.color.y), f64(light.color.z)}
		radiance.x += albedo.x * color.x * scale
		radiance.y += albedo.y * color.y * scale
		radiance.z += albedo.z * color.z * scale
	}
	return
}

// The GLSL and Odin encoders are one contract. The shader mirror is the oct
// pair in docs/research/lightmap-boxes.md.
oct_encode :: proc(direction: DVec3) -> [2]f64 {
	value := dv_mul(direction, 1.0 / (math.abs(direction.x) + math.abs(direction.y) + math.abs(direction.z)))
	if value.y < 0 {
		value.x, value.z = oct_wrap(value.x, value.z)
	}
	return {value.x * 0.5 + 0.5, value.z * 0.5 + 0.5}
}

oct_decode :: proc(uv: [2]f64) -> DVec3 {
	x := uv.x * 2.0 - 1.0
	y := uv.y * 2.0 - 1.0
	direction := DVec3{x, 1.0 - math.abs(x) - math.abs(y), y}
	if direction.y < 0 {
		direction.x, direction.z = oct_wrap(direction.x, direction.z)
	}
	return dv_normalize(direction)
}

@(private)
oct_wrap :: proc(x, z: f64) -> (f64, f64) {
	wrapped_x := (1.0 - math.abs(z)) * (x >= 0 ? 1.0 : -1.0)
	wrapped_z := (1.0 - math.abs(x)) * (z >= 0 ? 1.0 : -1.0)
	return wrapped_x, wrapped_z
}

probe_direction :: proc(index, count: int, rotation_x, rotation_y: f64) -> DVec3 {
	i := math.mod(f64(index) + 0.5 + rotation_x, f64(count))
	z := 1.0 - 2.0 * i / f64(count)
	radius := math.sqrt(max(0.0, 1.0 - z * z))
	angle := i * GOLDEN_ANGLE + rotation_y
	return {radius * math.cos(angle), z, radius * math.sin(angle)}
}

oct_texel_normal :: proc(x, y, size: int) -> DVec3 {
	return oct_decode({
		(f64(x) + 0.5) / f64(size),
		(f64(y) + 0.5) / f64(size),
	})
}

face_texel_position :: proc(
	box: geometry.Box,
	face, x, y, width, height: int,
) -> (position, normal: DVec3) {
	s := (f64(x) + 0.5) / f64(width)
	t := (f64(y) + 0.5) / f64(height)
	return face_point(box, face, s, t)
}
