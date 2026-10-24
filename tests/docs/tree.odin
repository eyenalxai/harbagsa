#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package docs_test

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
doc_paths_resolve :: proc(t: ^testing.T) {
	paths, paths_ok := doc_paths(t)
	if !paths_ok {
		return
	}
	defer doc_paths_close(paths)
	for doc_path in paths {
		doc, ok := doc_open(t, doc_path)
		if !ok {
			continue
		}
		for line, index in doc.lines {
			tokens := line_tokens(line)
			for token in tokens {
				if !is_doc_path(token) {
					continue
				}
				path := strip_line_ref(token)
				testing.expectf(
					t,
					os.exists(path),
					"%s:%d names %s, which does not exist",
					doc.path,
					index + 1,
					path,
				)
			}
			delete(tokens, context.allocator)
		}
		doc_close(&doc)
	}
}

@(test)
doc_line_references_are_in_range :: proc(t: ^testing.T) {
	paths, paths_ok := doc_paths(t)
	if !paths_ok {
		return
	}
	defer doc_paths_close(paths)
	for doc_path in paths {
		doc, ok := doc_open(t, doc_path)
		if !ok {
			continue
		}
		for line, index in doc.lines {
			tokens := line_tokens(line)
			for token in tokens {
				if !is_doc_path(token) {
					continue
				}
				ref := parse_line_ref(token)
				if !ref.ok {
					continue
				}
				if !os.exists(ref.path) {
					testing.expectf(
						t,
						false,
						"%s:%d references %s, which does not exist",
						doc.path,
						index + 1,
						ref.path,
					)
					continue
				}
				count, count_ok := file_line_count(ref.path)
				if !count_ok {
					testing.expectf(
						t,
						false,
						"%s:%d references %s, which cannot be read",
						doc.path,
						index + 1,
						ref.path,
					)
					continue
				}
				testing.expectf(
					t,
					ref.last <= count,
					"%s:%d references %s:%d-%d, but the file has %d lines",
					doc.path,
					index + 1,
					ref.path,
					ref.first,
					ref.last,
					count,
				)
			}
			delete(tokens, context.allocator)
		}
		doc_close(&doc)
	}
}

// Scenario names also appear inside fenced run commands, which the backtick
// token scan cannot see. Scan the raw line so a rename cannot go stale.
@(test)
doc_scenario_paths_resolve :: proc(t: ^testing.T) {
	paths, paths_ok := doc_paths(t)
	if !paths_ok {
		return
	}
	defer doc_paths_close(paths)
	total := 0
	for doc_path in paths {
		doc, ok := doc_open(t, doc_path)
		if !ok {
			continue
		}
		for line, index in doc.lines {
			cursor := 0
			for {
				rest := line[cursor:]
				at := strings.index(rest, "scenarios/")
				if at < 0 {
					break
				}
				start := cursor + at
				end := start + len("scenarios/")
				for end < len(line) && scenario_path_byte(line[end]) {
					end += 1
				}
				path := line[start:end]
				if strings.has_suffix(path, ".json") {
					total += 1
					testing.expectf(
						t,
						os.exists(path),
						"%s:%d names %s, which does not exist",
						doc.path,
						index + 1,
						path,
					)
				}
				cursor = max(end, start + 1)
			}
		}
		doc_close(&doc)
	}
	testing.expectf(t, total > 0, "no scenario references found in %v", DOC_DIRS)
}

@(private)
scenario_path_byte :: proc(b: byte) -> bool {
	return(b >= 'a' && b <= 'z') ||
		(b >= 'A' && b <= 'Z') ||
		(b >= '0' && b <= '9') ||
		b == '.' ||
		b == '-' ||
		b == '_' ||
		b == '/'
}

@(test)
doc_links_resolve :: proc(t: ^testing.T) {
	paths, paths_ok := doc_paths(t)
	if !paths_ok {
		return
	}
	defer doc_paths_close(paths)
	for doc_path in paths {
		doc, ok := doc_open(t, doc_path)
		if !ok {
			continue
		}
		base := doc_directory(doc.path)
		for line, index in doc.lines {
			rest := line
			for {
				open := strings.index(rest, "](")
				if open < 0 {
					break
				}
				rest = rest[open + 2:]
				close := strings.index_byte(rest, ')')
				if close < 0 {
					break
				}
				target := strings.trim_space(rest[:close])
				rest = rest[close + 1:]
				if target == "" ||
				   strings.has_prefix(target, "http://") ||
				   strings.has_prefix(target, "https://") ||
				   strings.has_prefix(target, "#") {
					continue
				}

				path := target
				if hash := strings.index_byte(path, '#'); hash >= 0 {
					path = path[:hash]
				}
				full_text: [512]byte
				full := fmt.bprintf(full_text[:], "%s%s", base, path)
				testing.expectf(
					t,
					os.exists(full),
					"%s:%d links %s, which resolves to %s and does not exist",
					doc.path,
					index + 1,
					target,
					full,
				)
			}
		}
		doc_close(&doc)
	}
}

doc_directory :: proc(path: string) -> string {
	slash := strings.last_index_byte(path, '/')
	if slash < 0 {
		return ""
	}
	return path[:slash + 1]
}
