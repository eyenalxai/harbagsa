#+vet explicit-allocators
#+vet !unused-procedures // @(test) procs are called by the test runner, not by name
package harness_test

import "core:testing"

import "src:harness"

@(test)
state_sections_name_the_check_namespaces :: proc(t: ^testing.T) {
	cases := []struct {
		field:   string,
		section: harness.State_Section,
	} {
		{"player.position", .Player},
		{"static_boxes.0.center", .Static_Boxes},
		{"objects.1.position", .Objects},
		{"settings.display", .Settings},
		{"debug.palette.open", .Debug},
		{"sun.position", .Sun},
		{"menu.open", .Menu},
		{"notice.text", .Notice},
		{"rows.0.label", .Rows},
		{"render_digest", .Render_Digest},
	}
	for value in cases {
		sections := harness.state_section_for_field(value.field)
		testing.expectf(t, value.section in sections, "%s missed %v", value.field, value.section)
		testing.expect_value(t, card(sections), 1)
	}

	// The base fields are set on every build, so they need no row.
	for field in ([4]string{"frame", "camera.yaw_deg", "settle.frames", "renderer.active"}) {
		testing.expect_value(t, card(harness.state_section_for_field(field)), 0)
	}

	testing.expect_value(
		t,
		harness.state_section_for_field("digest"),
		harness.state_all_sections(),
	)
	testing.expect_value(t, card(harness.state_all_sections()), 10)
}

@(test)
check_other_builds_both_namespaces :: proc(t: ^testing.T) {
	session, error := harness.session_create(context.allocator)
	testing.expectf(t, error == "", "session create failed: %s", error)
	if error != "" {
		return
	}
	defer harness.session_destroy(&session)

	reply := execute(t, &session, `{"cmd":"sun","azimuth_deg":120,"elevation_deg":30}`)
	harness.reply_destroy(&reply, context.allocator)

	reply = execute(
		t,
		&session,
		`{"cmd":"check","field":"sun.azimuth_deg","op":"eq","other":"debug.sun.azimuth_deg","tolerance":0.01}`,
	)
	defer harness.reply_destroy(&reply, context.allocator)
	testing.expectf(t, reply.ok, "cross-namespace check failed: %s", reply.error)
}
