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

Check_Command :: struct {
	field:  string,
	op:     Check_Op,
	value:  Check_Value,
	warmup: int,
}
