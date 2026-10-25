#+vet explicit-allocators
#+vet !unused-procedures // the harness calls this table
package renderer

Report_Kind :: enum {
	Bool,
	Number,
	String,
}

Report_Value :: struct {
	kind:    Report_Kind,
	boolean: bool,
	number:  f64,
	text:    string,
}

Report_Field :: struct {
	path: string,
	get:  proc(report: ^Renderer_Report) -> Report_Value,
}

// One row per reported field. The harness check paths read this table, and the
// tests reflect the report struct to fail when a field has no row.
REPORT_FIELDS := [?]Report_Field {
	{"active", report_active},
	{"frame_count", report_frame_count},
	{"taa_enabled", report_taa_enabled},
	{"jitter_index", report_jitter_index},
	{"history_valid", report_history_valid},
	{"convergence_frames", report_convergence_frames},
	{"history_read", report_history_read},
	{"history_weight", report_history_weight},
	{"reset_count", report_reset_count},
	{"last_reset", report_last_reset},
	{"shadow_phase", report_shadow_phase},
	{"light_count", report_light_count},
	{"atlas_weight", report_atlas_weight},
	{"text_truncated_runs", report_text_truncated_runs},
	{"text_font_drops", report_text_font_drops},
	{"debug.active", debug_active},
	{"debug.taa", debug_taa},
	{"debug.jitter", debug_jitter},
	{"debug.history_weight", debug_history_weight},
	{"debug.clamp", debug_clamp},
	{"debug.depth_trust", debug_depth_trust},
	{"debug.shadow_phase_frozen", debug_shadow_phase_frozen},
	{"debug.shadow_phase", debug_shadow_phase},
	{"debug.light_shadows", debug_light_shadows},
	{"debug.synthetic_lights", debug_synthetic_lights},
	{"debug.sky", debug_sky},
	{"debug.ao", debug_ao},
}

report_field :: proc(report: ^Renderer_Report, path: string) -> (Report_Value, bool) {
	for field in REPORT_FIELDS {
		if field.path == path {
			return field.get(report), true
		}
	}
	return {}, false
}

@(private)
report_active :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Bool, boolean = report.active}}
@(private)
report_frame_count :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Number, number = f64(report.frame_count)}}
@(private)
report_taa_enabled :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Bool, boolean = report.taa_enabled}}
@(private)
report_jitter_index :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Number, number = f64(report.jitter_index)}}
@(private)
report_history_valid :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Bool, boolean = report.history_valid}}
@(private)
report_convergence_frames :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Number, number = f64(report.convergence_frames)}}
@(private)
report_history_read :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Number, number = f64(report.history_read)}}
@(private)
report_history_weight :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Number, number = f64(report.history_weight)}}
@(private)
report_reset_count :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Number, number = f64(report.reset_count)}}
@(private)
report_last_reset :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .String, text = report.last_reset}}
@(private)
report_shadow_phase :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Number, number = f64(report.shadow_phase)}}
@(private)
report_light_count :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Number, number = f64(report.light_count)}}
@(private)
report_atlas_weight :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Number, number = f64(report.atlas_weight)}}
@(private)
report_text_truncated_runs :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Number, number = f64(report.text_truncated_runs)}}
@(private)
report_text_font_drops :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Number, number = f64(report.text_font_drops)}}
@(private)
debug_active :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Bool, boolean = report.debug.active}}
@(private)
debug_taa :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Bool, boolean = report.debug.taa}}
@(private)
debug_jitter :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Bool, boolean = report.debug.jitter}}
@(private)
debug_history_weight :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Number, number = f64(report.debug.history_weight)}}
@(private)
debug_clamp :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Bool, boolean = report.debug.clamp}}
@(private)
debug_depth_trust :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Bool, boolean = report.debug.depth_trust}}
@(private)
debug_shadow_phase_frozen :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Bool, boolean = report.debug.shadow_phase_frozen}}
@(private)
debug_shadow_phase :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Number, number = f64(report.debug.shadow_phase)}}
@(private)
debug_light_shadows :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Bool, boolean = report.debug.light_shadows}}
@(private)
debug_synthetic_lights :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Number, number = f64(report.debug.synthetic_lights)}}
@(private)
debug_sky :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Bool, boolean = report.debug.sky}}
@(private)
debug_ao :: proc(report: ^Renderer_Report) -> Report_Value {return {kind = .Bool, boolean = report.debug.ao}}
