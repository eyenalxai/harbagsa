#+vet explicit-allocators
package geometry

// A unit quaternion that leaves a box axis-aligned.
IDENTITY_ROTATION :: [4]f32{0, 0, 0, 1}

// Box is one axis-aligned box in a scene. Center is the box center and
// half_extents is half its size on each axis. Rotation is a quaternion in
// x, y, z, w order. Color belongs to presentation only.
Box :: struct {
	center:       [3]f32,
	half_extents: [3]f32,
	color:        [4]f32,
	rotation:     [4]f32,
}
