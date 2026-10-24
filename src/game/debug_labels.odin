#+vet explicit-allocators
#+vet !unused-procedures // the agent harness reads these names; the game binary does not
package game

debug_selection_name :: proc(selection: Debug_Selection) -> string {
	switch selection {
	case .None:
		return "none"
	case .Object:
		return "object"
	case .Sun:
		return "sun"
	}
	return "none"
}
