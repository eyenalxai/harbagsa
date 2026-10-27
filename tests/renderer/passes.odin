#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package renderer_test

import "core:testing"

import "src:perf"
import "src:renderer"
import vk "vendor:vulkan"

@(test)
the_pass_list_covers_every_perf_pass_in_order :: proc(t: ^testing.T) {
	testing.expect_value(t, len(perf.PASS_ORDER), perf.PASS_COUNT)
	for pass, index in perf.PASS_ORDER {
		testing.expect_value(t, pass, perf.Pass(index))
	}
	testing.expect_value(t, renderer.TIMESTAMP_COUNT, u32(perf.PASS_COUNT) + 1)
}

@(test)
every_pass_kind_builds_one_scope :: proc(t: ^testing.T) {
	r: renderer.Renderer
	r.target.config = {width = 1280, height = 720}
	r.target.views = make([]vk.ImageView, 1, context.temp_allocator)

	for kind in perf.PASS_ORDER {
		pass: renderer.Pass
		renderer.build_pass(&r, &pass, kind, 0, nil)
		testing.expect_value(t, pass.name, kind)
		testing.expect_value(
			t,
			pass.has_rendering,
			kind != .Tlas && kind != .Cluster,
		)
		has_barriers := pass.barriers != nil
		testing.expect_value(
			t,
			has_barriers,
			kind == .Depth || kind == .Scene || kind == .Taa,
		)
		has_after := pass.after != nil
		testing.expect_value(
			t,
			has_after,
			kind == .Taa || kind == .Cluster,
		)
	}
}
