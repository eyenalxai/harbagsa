#+vet explicit-allocators
package harness

import "core:encoding/json"

json_get :: proc(object: json.Object, key: string) -> (value: json.Value, ok: bool) {
	value, ok = object[key]
	return
}

json_get_required :: proc(object: json.Object, key: string) -> json.Value {
	value, _ := json_get(object, key)
	return value
}

json_number :: proc(value: json.Value) -> (result: f64, ok: bool) {
	#partial switch number in value {
	case json.Integer:
		return f64(number), true
	case json.Float:
		return number, true
	case:
		return 0, false
	}
}

json_integer :: proc(value: json.Value) -> (result: int, ok: bool) {
	#partial switch number in value {
	case json.Integer:
		if number < i64(min(int)) || number > i64(max(int)) {
			return 0, false
		}
		return int(number), true
	case:
		return 0, false
	}
}

json_boolean :: proc(value: json.Value) -> (result: bool, ok: bool) {
	#partial switch boolean in value {
	case json.Boolean:
		return boolean, true
	case:
		return false, false
	}
}

json_string :: proc(value: json.Value) -> (result: string, ok: bool) {
	#partial switch text in value {
	case json.String:
		return text, true
	case:
		return "", false
	}
}

json_array :: proc(value: json.Value) -> (result: json.Array, ok: bool) {
	#partial switch array in value {
	case json.Array:
		return array, true
	case:
		return {}, false
	}
}

json_is_null :: proc(value: json.Value) -> bool {
	_, ok := value.(json.Null)
	return ok
}

json_object :: proc(value: json.Value) -> (result: json.Object, ok: bool) {
	#partial switch object in value {
	case json.Object:
		return object, true
	case:
		return {}, false
	}
}

json_unknown_key :: proc(object: json.Object, allowed: []string) -> (key: string, found: bool) {
	for name in object {
		if !string_in(name, allowed) {
			return name, true
		}
	}
	return "", false
}

string_in :: proc(value: string, values: []string) -> bool {
	for candidate in values {
		if candidate == value {
			return true
		}
	}
	return false
}

@(private)
number_field :: proc(object: json.Object, key: string) -> (value: f64, ok: bool) {
	value_json, has := json_get(object, key)
	if !has {
		return 0, false
	}
	return json_number(value_json)
}

@(private)
integer_field :: proc(object: json.Object, key: string) -> (value: int, ok: bool) {
	value_json, has := json_get(object, key)
	if !has {
		return 0, false
	}
	return json_integer(value_json)
}

@(private)
string_field :: proc(object: json.Object, key: string) -> (value: string, ok: bool) {
	value_json, has := json_get(object, key)
	if !has {
		return "", false
	}
	return json_string(value_json)
}

// json_bool reads an optional boolean and leaves value alone when the key is absent.
// An empty return means success.
json_bool :: proc(object: json.Object, key: string, value: ^bool) -> string {
	raw, present := json_get(object, key)
	if !present {
		return ""
	}
	flag, ok := json_boolean(raw)
	if !ok {
		return format_error("'%s' must be a boolean", key)
	}
	value^ = flag
	return ""
}

json_optional_bool :: proc(object: json.Object, key: string, value: ^bool, has: ^bool) -> string {
	raw, present := json_get(object, key)
	if !present {
		return ""
	}
	flag, ok := json_boolean(raw)
	if !ok {
		return format_error("'%s' must be a boolean", key)
	}
	value^ = flag
	has^ = true
	return ""
}

@(private)
vec3_field :: proc(object: json.Object, key: string) -> (value: [3]f32, ok: bool) {
	value_json, has := json_get(object, key)
	if !has {
		return {}, false
	}
	array, array_ok := json_array(value_json)
	if !array_ok || len(array) != 3 {
		return {}, false
	}
	for index in 0 ..< 3 {
		number, number_ok := json_number(array[index])
		if !number_ok {
			return {}, false
		}
		value[index] = f32(number)
	}
	return value, true
}

vec2_int_field :: proc(object: json.Object, key: string) -> (value: [2]i32, ok: bool) {
	value_json, has := json_get(object, key)
	if !has {
		return {}, false
	}
	array, array_ok := json_array(value_json)
	if !array_ok || len(array) != 2 {
		return {}, false
	}
	for index in 0 ..< 2 {
		number, number_ok := json_integer(array[index])
		if !number_ok {
			return {}, false
		}
		value[index] = i32(number)
	}
	return value, true
}

@(private)
vec2_field :: proc(object: json.Object, key: string) -> (value: [2]f32, ok: bool) {
	value_json, has := json_get(object, key)
	if !has {
		return {}, false
	}
	array, array_ok := json_array(value_json)
	if !array_ok || len(array) != 2 {
		return {}, false
	}
	for index in 0 ..< 2 {
		number, number_ok := json_number(array[index])
		if !number_ok {
			return {}, false
		}
		value[index] = f32(number)
	}
	return value, true
}
