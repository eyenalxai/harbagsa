#+vet explicit-allocators
package harness

import "core:encoding/json"

json_get :: proc(object: json.Object, key: string) -> (value: json.Value, ok: bool) {
	value, ok = object[key]
	return
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
