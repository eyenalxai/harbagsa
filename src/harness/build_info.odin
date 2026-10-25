#+vet explicit-allocators
package harness

// The Makefile injects the short HEAD and the dirty state. A direct `odin run`
// or a test build keeps the fallback, so a report never claims a revision it
// does not know.
HARNESS_REVISION :: #config(HARNESS_REVISION, "unknown")
HARNESS_DIRTY :: #config(HARNESS_DIRTY, false)

// The Makefile quotes the revision so an all-digit hash stays a string. Odin
// keeps the quotes in the config value, so the report trims them.
trim_revision :: proc(text: string) -> string {
	if len(text) >= 2 && text[0] == '"' && text[len(text) - 1] == '"' {
		return text[1:len(text) - 1]
	}
	return text
}
