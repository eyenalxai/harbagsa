#+vet explicit-allocators
package geometry

IDENTITY_ROTATION :: [4]f32{0, 0, 0, 1}

Box :: struct {
	center:       [3]f32,
	half_extents: [3]f32,
	color:        [4]f32,
	rotation:     [4]f32,
	// A non-zero strength makes the box a lamp: it glows and it does not block
	// its own point light.
	emissive:     f32,
	visual_only:  bool,
}
