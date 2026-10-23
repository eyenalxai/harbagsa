#+vet explicit-allocators
package geometry

// Line is one world-space debug line segment. Color is linear RGBA and
// belongs to presentation only.
Line :: struct {
	from:  [3]f32,
	to:    [3]f32,
	color: [4]f32,
}
