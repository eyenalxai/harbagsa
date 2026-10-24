#+vet explicit-allocators
package main

Input_Latches :: struct {
	jump:   bool,
	sprint: bool,
	crouch: bool,
	prone:  bool,
}

clear_latches :: proc(latches: ^Input_Latches) {
	latches^ = {}
}
