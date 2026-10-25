#+vet explicit-allocators
#+vet !unused-procedures
package harness_test

import "core:encoding/json"
import "core:strings"
import "core:testing"

import "src:harness"

@(test)
setup_reports_the_build_revision_and_dirty_fallback :: proc(t: ^testing.T) {
	setup := harness.setup_build({width = 1280, height = 720}, {}, {})
	testing.expect_value(t, setup.revision, "unknown")
	testing.expect(t, !setup.dirty, "a test build is dirty")
	testing.expect_value(t, setup.target, "none")
	testing.expect_value(t, setup.renderer.ao_samples, 8)
	testing.expect_value(t, setup.renderer.ao_radius, f32(1.5))
	testing.expect_value(t, setup.renderer.ao_strength, f32(1.0))
	testing.expectf(t, len(setup.renderer.shader_digest) == 16, "the shader digest is %q", setup.renderer.shader_digest)

	data, error := json.marshal(harness.Report{setup = setup}, {}, context.allocator)
	defer delete(data, context.allocator)
	testing.expectf(t, error == nil, "report marshal failed: %v", error)
	text := string(data)
	testing.expect(t, strings.contains(text, `"revision":"unknown"`), "the revision is missing")
	testing.expect(t, strings.contains(text, `"dirty":false`), "the dirty flag is missing")
	testing.expect(t, strings.contains(text, `"ao_strength":1`), "the AO strength is missing")
	testing.expect(t, strings.contains(text, `"shader_digest"`), "the shader digest is missing")
}
