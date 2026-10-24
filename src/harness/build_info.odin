#+vet explicit-allocators
package harness

// The Makefile injects the short HEAD and the dirty state. A direct `odin run`
// or a test build keeps the fallback, so a report never claims a revision it
// does not know.
HARNESS_REVISION :: #config(HARNESS_REVISION, "unknown")
HARNESS_DIRTY :: #config(HARNESS_DIRTY, false)
