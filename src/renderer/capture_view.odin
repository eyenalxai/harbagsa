#+vet explicit-allocators
#+vet !unused-procedures // the harness names views; the game binary does not
package renderer

// The order is the push constant value the lit pass receives and the order of
// the shader constants in terms.glsl.
Capture_View :: enum {
	Beauty,
	Direct,
	Lightmap,
	Probe,
	Emissive,
	Shadow,
	Lightmap_Grid,
	Probe_Cell,
}

Capture_Views :: bit_set[Capture_View]

CAPTURE_VIEW_NAMES := [Capture_View]string {
	.Beauty        = "beauty",
	.Direct        = "direct",
	.Lightmap      = "lightmap",
	.Probe         = "probe",
	.Emissive      = "emissive",
	.Shadow        = "shadow",
	.Lightmap_Grid = "lightmap_grid",
	.Probe_Cell    = "probe_cell",
}

capture_view_name :: proc(view: Capture_View) -> string {
	if int(view) < 0 || int(view) >= len(CAPTURE_VIEW_NAMES) {
		return "beauty"
	}
	return CAPTURE_VIEW_NAMES[view]
}

capture_view_parse :: proc(name: string) -> (view: Capture_View, ok: bool) {
	for candidate in Capture_View {
		if CAPTURE_VIEW_NAMES[candidate] == name {
			return candidate, true
		}
	}
	return .Beauty, false
}

// Beauty is the existing resolve. Every other view is one extra lit pass into a
// view image that resolves without history.
capture_view_is_term :: proc(view: Capture_View) -> bool {
	return view != .Beauty
}
