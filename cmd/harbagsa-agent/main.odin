#+vet explicit-allocators
package main

import "core:os"

import "src:harness"

main :: proc() {
	os.exit(harness.cli_main())
}
