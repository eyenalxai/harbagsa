#+vet explicit-allocators
package harness

import "src:game"

// The command and the object both hold the name inline, so a parsed scenario
// has no name allocation to free on a command error.
Object_Name :: struct {
	bytes:  [game.OBJECT_NAME_BYTES]u8,
	length: u8,
}

object_name_from_text :: proc(text: string) -> (Object_Name, bool) {
	if !game.object_name_valid(text) {
		return {}, false
	}
	name: Object_Name
	name.length = u8(len(text))
	copy(name.bytes[:], text)
	return name, true
}

object_name_text :: proc(name: ^Object_Name) -> string {
	return string(name.bytes[:name.length])
}
