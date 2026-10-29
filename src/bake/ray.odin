#+vet explicit-allocators
package bake

Hit :: struct {
	t:      f64,
	box:    int,
	normal: DVec3,
	front:  bool,
}

Ray :: struct {
	origin:    DVec3,
	direction: DVec3,
	inverse:   DVec3,
}

ray_make :: proc(origin, direction: DVec3) -> Ray {
	inverse: DVec3
	for axis in 0 ..< 3 {
		inverse[axis] = abs(direction[axis]) <= 1e-15 ? 0 : 1.0 / direction[axis]
	}
	return {origin = origin, direction = direction, inverse = inverse}
}
ray_cast :: proc(bvh: ^Bvh, ray: Ray, tmin, tmax: f64) -> (Hit, bool) #no_bounds_check {
	best := Hit{t = tmax}
	found := false
	stack: [BVH_MAX_DEPTH]u32
	depth := 0
	if len(bvh.nodes) == 0 {
		return best, false
	}
	stack[depth] = 0
	depth += 1
	for depth > 0 {
		depth -= 1
		node := bvh.nodes[stack[depth]]
		if !ray_bounds(ray, node.bounds, tmin, best.t) {
			continue
		}
		if node.count > 0 {
			for offset in 0 ..< int(node.count) {
				index := int(bvh.order[int(node.start) + offset])
				hit, hit_ok := ray_box(bvh, index, ray, tmin, best.t)
				if hit_ok && hit.t < best.t {
					best = hit
					found = true
				}
			}
			continue
		}
		if depth + 2 <= BVH_MAX_DEPTH {
			near_child := node.left
			far_child := node.right
			if ray.origin[int(node.axis)] > node.split {
				near_child = node.right
				far_child = node.left
			}
			stack[depth] = far_child
			stack[depth + 1] = near_child
			depth += 2
		}
	}
	return best, found
}

// Shadow rays use the same mask rule as the frame: a lamp or any emissive box
// does not block a point light.
shadow_occluded :: proc(bvh: ^Bvh, ray: Ray, tmin, tmax: f64) -> bool #no_bounds_check {
	if tmax <= tmin || len(bvh.nodes) == 0 {
		return false
	}
	stack: [BVH_MAX_DEPTH]u32
	depth := 0
	stack[depth] = 0
	depth += 1
	for depth > 0 {
		depth -= 1
		node := bvh.nodes[stack[depth]]
		if !ray_bounds(ray, node.bounds, tmin, tmax) {
			continue
		}
		if node.count > 0 {
			for offset in 0 ..< int(node.count) {
				index := int(bvh.order[int(node.start) + offset])
				if bvh.boxes[index].box.emissive > 0 {
					continue
				}
				_, hit_ok := ray_box(bvh, index, ray, tmin, tmax)
				if hit_ok {
					return true
				}
			}
			continue
		}
		if depth + 2 <= BVH_MAX_DEPTH {
			near_child := node.left
			far_child := node.right
			if ray.origin[int(node.axis)] > node.split {
				near_child = node.right
				far_child = node.left
			}
			stack[depth] = far_child
			stack[depth + 1] = near_child
			depth += 2
		}
	}
	return false
}

@(private)
ray_bounds :: #force_inline proc(ray: Ray, bounds: Bounds, tmin, tmax: f64) -> bool #no_bounds_check {
	t_near := tmin
	t_far := tmax
	for axis in 0 ..< 3 {
		origin := ray.origin[axis]
		direction := ray.direction[axis]
		if abs(direction) <= 1e-15 {
			if origin < bounds.lower[axis] || origin > bounds.upper[axis] {
				return false
			}
			continue
		}
		inverse := ray.inverse[axis]
		first := (bounds.lower[axis] - origin) * inverse
		second := (bounds.upper[axis] - origin) * inverse
		if first > second {
			first, second = second, first
		}
		t_near = max(t_near, first)
		t_far = min(t_far, second)
		if t_near > t_far {
			return false
		}
	}
	return true
}

@(private)
ray_box :: proc(bvh: ^Bvh, index: int, ray: Ray, tmin, tmax: f64) -> (Hit, bool) #no_bounds_check {
	entry := bvh.boxes[index]
	center := dv(entry.box.center)
	half := dv(entry.box.half_extents)
	local_origin: DVec3
	local_inverse: DVec3
	if bvh.identity[index] {
		local_origin = dv_sub(ray.origin, center)
		local_inverse = ray.inverse
	} else {
		local_origin = quat_inverse_rotate(bvh.rotations[index], dv_sub(ray.origin, center))
		local_direction := quat_inverse_rotate(bvh.rotations[index], ray.direction)
		for component in 0 ..< 3 {
			if abs(local_direction[component]) <= 1e-15 {
				local_inverse[component] = 0
			} else {
				local_inverse[component] = 1.0 / local_direction[component]
			}
		}
	}

	t_enter := f64(-1e30)
	t_exit := f64(1e30)
	axis := -1
	sign := 0.0
	for component in 0 ..< 3 {
		extent := half[component]
		origin := local_origin[component]
		inverse := local_inverse[component]
		if inverse == 0 {
			if origin < -extent || origin > extent {
				return {}, false
			}
			continue
		}
		near := (-extent - origin) * inverse
		far := (extent - origin) * inverse
		face := -1.0
		if near > far {
			near, far = far, near
			face = 1.0
		}
		if near > t_enter {
			t_enter = near
			axis = component
			sign = face
		}
		t_exit = min(t_exit, far)
		if t_enter > t_exit {
			return {}, false
		}
	}
	if axis < 0 || t_enter < tmin || t_enter > tmax {
		return {}, false
	}

	local_normal := dv_mul(dv_axis(axis), sign)
	normal := bvh.identity[index] ? local_normal : quat_rotate(bvh.rotations[index], local_normal)
	return {
		t = t_enter,
		box = index,
		normal = normal,
		front = dv_dot(normal, ray.direction) < 0,
	}, true
}

