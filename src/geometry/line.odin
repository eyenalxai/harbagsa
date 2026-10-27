#+vet explicit-allocators
package geometry

// The renderer shares one debug buffer between the world, the selection outline,
// and the placement ghost. The source names which owner added the line, so a
// report can tell an empty gizmo from a dim one.
Line_Kind :: enum u8 {
	World,
	Selection,
	Placement,
}

LINE_KIND_COUNT :: len(Line_Kind)

Line :: struct {
	from:  [3]f32,
	to:    [3]f32,
	color: [4]f32,
	kind:  Line_Kind,
}
