#+vet explicit-allocators
package bake

import "core:mem"

BVH_LEAF_SIZE :: 4
BVH_MAX_DEPTH :: 64

Bounds :: struct {
	lower: DVec3,
	upper: DVec3,
}

Bvh_Node :: struct {
	bounds: Bounds,
	left:   u32,
	right:  u32,
	start:  u32,
	count:  u32,
	axis:   u8,
	split:  f64,
}

Bvh :: struct {
	nodes:     [dynamic]Bvh_Node,
	order:     []u32,
	boxes:     []Box_Entry,
	rotations: []DQuat,
	identity:  []bool,
}

bvh_build :: proc(static: Static, allocator: mem.Allocator) -> (Bvh, Build_Error) {
	count := len(static.boxes)
	if count == 0 {
		return {}, .No_Static_Boxes
	}
	bvh := Bvh {
		nodes     = make([dynamic]Bvh_Node, 0, 0, allocator),
		order     = make([]u32, count, allocator),
		boxes     = static.boxes,
		rotations = make([]DQuat, count, allocator),
		identity  = make([]bool, count, allocator),
	}
	centroids := make([]DVec3, count, allocator)
	bounds := make([]Bounds, count, allocator)
	defer delete(centroids, allocator)
	defer delete(bounds, allocator)

	for entry, index in static.boxes {
		rotation, rotation_ok := quat_normalize(entry.box.rotation)
		if !rotation_ok {
			bvh_destroy(&bvh, allocator)
			return {}, .Bad_Box
		}
		lower, upper := box_world_bounds(entry.box)
		if !bounds_finite(lower, upper) {
			bvh_destroy(&bvh, allocator)
			return {}, .Bad_Box
		}
		bvh.rotations[index] = rotation
		bvh.identity[index] =
			rotation.x == 0 && rotation.y == 0 && rotation.z == 0 && rotation.w == 1
		bounds[index] = {lower, upper}
		centroids[index] = dv_mul(dv_add(lower, upper), 0.5)
		bvh.order[index] = u32(index)
	}

builder := Bvh_Builder {
		bvh       = &bvh,
		centroids = centroids,
		bounds    = bounds,
	}
	if !bvh_build_node(&builder, 0, count) {
		bvh_destroy(&bvh, allocator)
		return {}, .Bad_Box
	}
	return bvh, .None
}

bvh_destroy :: proc(bvh: ^Bvh, allocator: mem.Allocator) {
	if bvh.nodes != nil {
		delete(bvh.nodes)
	}
	if bvh.order != nil {
		delete(bvh.order, allocator)
	}
	if bvh.rotations != nil {
		delete(bvh.rotations, allocator)
	}
	if bvh.identity != nil {
		delete(bvh.identity, allocator)
	}
	bvh^ = {}
}

@(private)
Bvh_Builder :: struct {
	bvh:       ^Bvh,
	centroids: []DVec3,
	bounds:    []Bounds,
}

@(private)
bvh_build_node :: proc(builder: ^Bvh_Builder, start, count: int) -> bool {
	if count <= 0 {
		return false
	}
	node_index := len(builder.bvh.nodes)
	append(&builder.bvh.nodes, Bvh_Node{})

	if count <= BVH_LEAF_SIZE {
		builder.bvh.nodes[node_index] = {
			bounds = bounds_for(builder, start, count),
			start  = u32(start),
			count  = u32(count),
		}
		return true
	}

	axis := split_axis(builder.centroids, builder.bvh.order, start, count)
	sort_range(builder.centroids, builder.bvh.order, start, count, axis)
	mid := start + count / 2
	left := u32(len(builder.bvh.nodes))
	if !bvh_build_node(builder, start, mid - start) {
		return false
	}
	right := u32(len(builder.bvh.nodes))
	if !bvh_build_node(builder, mid, start + count - mid) {
		return false
	}
	builder.bvh.nodes[node_index] = {
		bounds = bounds_union(builder.bvh.nodes[left].bounds, builder.bvh.nodes[right].bounds),
		left   = left,
		right  = right,
		count  = 0,
		axis   = u8(axis),
		split  = builder.centroids[builder.bvh.order[mid]][axis],
	}
	return true
}

@(private)
split_axis :: proc(centroids: []DVec3, order: []u32, start, count: int) -> int {
	lower := centroids[order[start]]
	upper := lower
	for index in start + 1 ..< start + count {
		value := centroids[order[index]]
		lower.x = min(lower.x, value.x)
		lower.y = min(lower.y, value.y)
		lower.z = min(lower.z, value.z)
		upper.x = max(upper.x, value.x)
		upper.y = max(upper.y, value.y)
		upper.z = max(upper.z, value.z)
	}
	extent := dv_sub(upper, lower)
	if extent.y > extent.x && extent.y >= extent.z {
		return 1
	}
	if extent.z > extent.x && extent.z > extent.y {
		return 2
	}
	return 0
}

@(private)
sort_range :: proc(centroids: []DVec3, order: []u32, start, count, axis: int) {
	for index in start + 1 ..< start + count {
		value := order[index]
		cursor := index
		for cursor > start && order_less(centroids, value, order[cursor - 1], axis) {
			order[cursor] = order[cursor - 1]
			cursor -= 1
		}
		order[cursor] = value
	}
}

@(private)
order_less :: proc(centroids: []DVec3, a, b: u32, axis: int) -> bool {
	left := centroids[a][axis]
	right := centroids[b][axis]
	if left < right {
		return true
	}
	if left > right {
		return false
	}
	return a < b
}

@(private)
bounds_for :: proc(builder: ^Bvh_Builder, start, count: int) -> Bounds {
	bounds := builder.bounds[builder.bvh.order[start]]
	for index in start + 1 ..< start + count {
		bounds = bounds_union(bounds, builder.bounds[builder.bvh.order[index]])
	}
	return bounds
}

@(private)
bounds_union :: proc(a, b: Bounds) -> Bounds {
	return {
		lower = {
			min(a.lower.x, b.lower.x),
			min(a.lower.y, b.lower.y),
			min(a.lower.z, b.lower.z),
		},
		upper = {
			max(a.upper.x, b.upper.x),
			max(a.upper.y, b.upper.y),
			max(a.upper.z, b.upper.z),
		},
	}
}

@(private)
bounds_finite :: proc(lower, upper: DVec3) -> bool {
	for index in 0 ..< 3 {
		if !finite_f64(lower[index]) || !finite_f64(upper[index]) {
			return false
		}
		if lower[index] > upper[index] {
			return false
		}
	}
	return true
}
