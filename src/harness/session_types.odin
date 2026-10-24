#+vet explicit-allocators
package harness

View :: struct {
	hud:   bool,
	debug: bool,
	hint:  bool,
	perf:  bool,
}

Pending_Capture :: struct {
	name:  string,
	frame: int,
	alpha: f32,
}
