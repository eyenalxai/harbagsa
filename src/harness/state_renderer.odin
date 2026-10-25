#+vet explicit-allocators
package harness

import "core:fmt"

import "src:renderer"

@(private)
renderer_field :: proc(state: renderer.Renderer_Report, path: string) -> (Check_Value, string) {
	report := state
	value, found := renderer.report_field(&report, path)
	if !found {
		return {}, fmt.aprintf("unknown renderer field %q", path, allocator = context.allocator)
	}
	switch value.kind {
	case .Bool:
		return {kind = .Bool, boolean = value.boolean}, ""
	case .Number:
		return {kind = .Number, number = value.number}, ""
	case .String:
		return {kind = .String, text = value.text}, ""
	}
	return {}, fmt.aprintf("unknown renderer field %q", path, allocator = context.allocator)
}
