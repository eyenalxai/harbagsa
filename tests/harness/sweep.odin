#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:fmt"
import "core:strings"
import "core:testing"

import "src:harness"

@(test)
parameter_sweep_parses_values_in_order :: proc(t: ^testing.T) {
	sweep, error := harness.parse_parameter_sweep("lamp_x=20,19.999,19.99", context.allocator)
	testing.expectf(t, error == "", "sweep parse failed: %s", error)
	defer delete(sweep.values, context.allocator)
	if error != "" {
		return
	}
	testing.expect_value(t, sweep.name, "lamp_x")
	testing.expect_value(t, len(sweep.values), 3)
	testing.expect_value(t, sweep.values[1], "19.999")
}

@(test)
parameter_sweep_rejects_bad_values :: proc(t: ^testing.T) {
	bad := []string{"lamp_x", "lamp_x=", "lamp_x=1,,2", "lamp x=1", "lamp_x=1,1"}
	for line in bad {
		_, error := harness.parse_parameter_sweep(line, context.allocator)
		testing.expectf(t, error != "", "bad sweep was accepted: %s", line)
		if error != "" {
			delete(error, context.allocator)
		}
	}
}

@(test)
sweep_combinations_count_like_an_odometer :: proc(t: ^testing.T) {
	parameters := []harness.Parameter_Sweep {
		{name = "x", values = []string{"1", "2"}},
		{name = "y", values = []string{"a", "b", "c"}},
	}
	testing.expect_value(t, harness.sweep_combination_count(parameters), 6)

	buffer: [harness.MAX_SWEEP_PARAMETERS]harness.Parameter_Override
	expected := []string{"x=1,y=a", "x=1,y=b", "x=1,y=c", "x=2,y=a", "x=2,y=b", "x=2,y=c"}
	for index in 0 ..< 6 {
		combination := harness.sweep_combination(parameters, index, buffer[:])
		text := fmt.aprintf(
			"%s=%s,%s=%s",
			combination[0].name,
			combination[0].value,
			combination[1].name,
			combination[1].value,
			allocator = context.temp_allocator,
		)
		testing.expect_value(t, text, expected[index])
	}
}

@(test)
sweep_label_names_the_values :: proc(t: ^testing.T) {
	overrides := []harness.Parameter_Override {
		{name = "lamp_x", value = "19.999"},
		{name = "mode", value = "warm_light"},
	}
	label := harness.sweep_label(overrides, context.allocator)
	defer delete(label, context.allocator)
	testing.expect_value(t, label, "lamp_x=19.999,mode=warm_light")
}

@(test)
sweep_label_marks_a_replacement_with_a_hash :: proc(t: ^testing.T) {
	overrides := []harness.Parameter_Override{{name = "label", value = "a b"}}
	label := harness.sweep_label(overrides, context.allocator)
	defer delete(label, context.allocator)
	testing.expect(t, strings.has_prefix(label, "label=a_b-"), "the replaced value has no hash suffix")
	testing.expect(t, len(label) == len("label=a_b-") + 4, "the hash suffix is not four characters")
}
