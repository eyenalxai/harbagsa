#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:encoding/json"
import "core:testing"

import "src:harness"

@(test)
json_bool_reads_presence_and_type :: proc(t: ^testing.T) {
	object := make(json.Object, 1, context.allocator)
	defer delete(object)
	object["flag"] = json.Boolean(true)

	value := false
	testing.expect_value(t, harness.json_bool(object, "missing", &value), "")
	testing.expect(t, !value)

	testing.expect_value(t, harness.json_bool(object, "flag", &value), "")
	testing.expect(t, value)

	object["flag"] = json.String("yes")
	has := false
	value = false
	field_error := harness.json_optional_bool(object, "flag", &value, &has)
	testing.expect(t, field_error != "", "a string was accepted as a boolean")
	testing.expect(t, !has, "a failed parse set the presence flag")
	testing.expect(t, !value, "a failed parse changed the value")
	delete(field_error, context.allocator)
}
