#+vet explicit-allocators
package harness

Check_Op :: enum {
	Eq,
	Ne,
	Lt,
	Le,
	Gt,
	Ge,
}

Value_Kind :: enum {
	Number,
	Bool,
	String,
}

Check_Value :: struct {
	kind:    Value_Kind,
	number:  f64,
	boolean: bool,
	text:    string,
}

Capture_Window :: struct {
	start: int,
	count: int,
	has:   bool,
}

Check_Command :: struct {
	field:  string,
	op:     Check_Op,
	value:  Check_Value,
	warmup: int,
	window: Capture_Window,
}

check_op_name :: proc(op: Check_Op) -> string {
	switch op {
	case .Eq:
		return "eq"
	case .Ne:
		return "ne"
	case .Lt:
		return "lt"
	case .Le:
		return "le"
	case .Gt:
		return "gt"
	case .Ge:
		return "ge"
	}
	return "eq"
}

check_op_parse :: proc(name: string) -> (op: Check_Op, ok: bool) {
	switch name {
	case "eq":
		return .Eq, true
	case "ne":
		return .Ne, true
	case "lt":
		return .Lt, true
	case "le":
		return .Le, true
	case "gt":
		return .Gt, true
	case "ge":
		return .Ge, true
	}
	return .Eq, false
}
