#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package docs_test

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:testing"

DOC_DIRS := [?]string{"docs/ui", "docs/design", "docs/evidence"}

TABLE_CELL_MAX :: 8

doc_paths :: proc(t: ^testing.T) -> (paths: []string, ok: bool) {
	result := make([dynamic]string, 0, 16, context.allocator)
	ok = true
	for dir in DOC_DIRS {
		entries, read_error := os.read_all_directory_by_path(dir, context.allocator)
		if read_error != nil {
			testing.expectf(t, false, "cannot list %s: %v", dir, read_error)
			ok = false
			break
		}
		for entry in entries {
			if entry.type != .Regular || !strings.has_suffix(entry.name, ".md") {
				continue
			}
			path_text: [512]byte
			path := fmt.bprintf(path_text[:], "%s/%s", dir, entry.name)
			append(&result, strings.clone(path, context.allocator))
		}
		for entry in entries {
			os.file_info_delete(entry, context.allocator)
		}
		delete(entries, context.allocator)
	}
	if !ok {
		doc_paths_close(result[:])
		return nil, false
	}
	return result[:], true
}

doc_paths_close :: proc(paths: []string) {
	for path in paths {
		delete(path, context.allocator)
	}
	delete(paths, context.allocator)
}

Doc :: struct {
	path:  string,
	data:  []byte,
	lines: []string,
}

doc_open :: proc(t: ^testing.T, path: string) -> (doc: Doc, ok: bool) {
	data, read_error := os.read_entire_file(path, context.allocator)
	if read_error != nil {
		testing.expectf(t, false, "cannot read %s: %v", path, read_error)
		return {}, false
	}
	text := string(data)
	lines, split_error := strings.split_lines(text, context.allocator)
	if split_error != nil {
		testing.expectf(t, false, "cannot split %s: %v", path, split_error)
		delete(data, context.allocator)
		return {}, false
	}
	return Doc{path = path, data = data, lines = lines}, true
}

doc_close :: proc(doc: ^Doc) {
	delete(doc.lines, context.allocator)
	delete(doc.data, context.allocator)
}

// A table row is split on '|' and trimmed. The outer pipes yield an empty first
// and last field, so they are dropped.
split_table_row :: proc(line: string) -> (cells: [TABLE_CELL_MAX]string, count: int) {
	trimmed := strings.trim_space(line)
	if !strings.has_prefix(trimmed, "|") {
		return {}, 0
	}
	parts := strings.split(trimmed, "|", context.allocator)
	defer delete(parts, context.allocator)
	if len(parts) < 3 {
		return {}, 0
	}
	for part, index in parts[1:len(parts) - 1] {
		if index >= TABLE_CELL_MAX {
			break
		}
		cells[index] = strings.trim_space(part)
		count += 1
	}
	return
}

strip_ticks :: proc(cell: string) -> string {
	if len(cell) >= 2 && cell[0] == '`' && cell[len(cell) - 1] == '`' {
		return cell[1:len(cell) - 1]
	}
	return cell
}

// A palette row carries a backticked hex in its second cell. The helper returns
// false for a row that is not a palette row, and reports a malformed hex.
parse_palette_hex :: proc(t: ^testing.T, doc_path: string, line: int, cell: string) -> (hex: u32, ok: bool) {
	text := strip_ticks(cell)
	if !strings.has_prefix(text, "#") {
		return 0, false
	}
	value, parsed := strconv.parse_u64(text[1:], 16)
	if !parsed {
		testing.expectf(t, false, "%s:%d has an unreadable hex %q", doc_path, line, text)
		return 0, false
	}
	return u32(value), true
}

// Inline code spans are the odd pieces of a split on the backtick. The caller
// deletes the slice.
line_tokens :: proc(line: string) -> []string {
	parts := strings.split(line, "`", context.allocator)
	tokens := make([dynamic]string, 0, len(parts) / 2, context.allocator)
	for part, index in parts {
		if index % 2 == 1 {
			append(&tokens, strings.trim_space(part))
		}
	}
	delete(parts, context.allocator)
	return tokens[:]
}

approx_equal :: proc(a, b: f32) -> bool {
	difference := a - b
	return difference < 0.0005 && difference > -0.0005
}

is_doc_path :: proc(token: string) -> bool {
	return strings.has_prefix(token, "src/") ||
		strings.has_prefix(token, "tests/") ||
		strings.has_prefix(token, "docs/") ||
		strings.has_prefix(token, "scenarios/")
}

Line_Ref :: struct {
	path:  string,
	first: int,
	last:  int,
	ok:    bool,
}

parse_line_ref :: proc(token: string) -> Line_Ref {
	colon := strings.last_index_byte(token, ':')
	if colon <= 0 {
		return {}
	}
	rest := token[colon + 1:]
	first_text := rest
	last_text := rest
	if dash := strings.index_byte(rest, '-'); dash >= 0 {
		first_text = rest[:dash]
		last_text = rest[dash + 1:]
	}
	first, first_ok := strconv.parse_int(first_text)
	last, last_ok := strconv.parse_int(last_text)
	if !first_ok || !last_ok || first < 1 || last < first {
		return {}
	}
	return {path = token[:colon], first = first, last = last, ok = true}
}

strip_line_ref :: proc(token: string) -> string {
	ref := parse_line_ref(token)
	if ref.ok {
		return ref.path
	}
	return token
}

file_line_count :: proc(path: string) -> (count: int, ok: bool) {
	data, read_error := os.read_entire_file(path, context.allocator)
	if read_error != nil {
		return 0, false
	}
	defer delete(data, context.allocator)
	for byte in data {
		if byte == '\n' {
			count += 1
		}
	}
	if len(data) > 0 && data[len(data) - 1] != '\n' {
		count += 1
	}
	return count, true
}
