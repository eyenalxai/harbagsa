#+vet explicit-allocators
package harness

Run_Options :: struct {
	using common:    Common_Options,
	scenario:        string,
	parameters:      [MAX_SWEEP_PARAMETERS]Parameter_Sweep,
	parameter_count: int,
}

Report :: struct {
	ok:          bool             `json:"ok"`,
	exit_code:   int              `json:"exit_code"`,
	scenario:    Scenario_Source  `json:"scenario"`,
	run_dir:     string           `json:"run_dir"`,
	frame:       int              `json:"frame"`,
	state:       State            `json:"state"`,
	setup:       Setup_State      `json:"setup"`,
	captures: []Capture_Result `json:"captures"`,
	picks:       []Pick_Result    `json:"picks,omitempty"`,
	failures:    []string         `json:"failures"`,
	digest:      string           `json:"digest"`,
	error:       string           `json:"error,omitempty"`,
	perf:        []Perf_Report    `json:"perf,omitempty"`,
	trace:       string           `json:"trace,omitempty"`,
}

Run_Summary :: struct {
	ok:            bool     `json:"ok"`,
	exit_code:     int      `json:"exit_code"`,
	run_dir:       string   `json:"run_dir"`,
	report:        string   `json:"report"`,
	state:         string   `json:"state"`,
	captures:   []string `json:"captures"`,
	digest:        string   `json:"digest"`,
	error:         string   `json:"error,omitempty"`,
	failure:       string   `json:"failure,omitempty"`,
}
