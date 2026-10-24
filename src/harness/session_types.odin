#+vet explicit-allocators
package harness

View :: struct {
	hud:   bool,
	debug: bool,
	hint:  bool,
	perf:  bool,
}

Pending_Capture :: struct {
	name:      string,
	frame:     int,
	alpha:     f32,
	target:    Capture_Target,
	format:    Capture_Format,
	region:    Maybe(Capture_Region),
	profile:   Maybe(Capture_Profile),
	crop:      Maybe(Capture_Crop),
	histogram: Maybe(int),
}
