#+vet explicit-allocators
package harness

View :: struct {
	hud:   bool,
	debug: bool,
	hint:  bool,
	perf:  bool,
}

Pending_Capture :: struct {
	frame:    int,
	alpha:    f32,
	requests: []Capture_Request,
}
