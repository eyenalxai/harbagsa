#+vet explicit-allocators
package harness

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"

// A clock probe is optional evidence. A missing tool, a missing driver, or a
// tool without a clock line all end in `unknown` and a warning, never a guess.
Perf_Clock :: struct {
	known:  bool        `json:"known"`,
	mhz:    Maybe(int)  `json:"mhz,omitempty"`,
	source: string      `json:"source,omitempty"`,
}

Perf_Load :: struct {
	available: bool  `json:"available"`,
	one:       f64   `json:"one"`,
	five:      f64   `json:"five"`,
	fifteen:   f64   `json:"fifteen"`,
}

// The renderer's device decides which vendor tool is asked first, so a hybrid
// host does not report the idle GPU's clock.
gpu_clock_probe :: proc(allocator: mem.Allocator, device: string) -> (Perf_Clock, string) {
	lower := strings.to_lower(device, context.temp_allocator)
	prefer_nvidia := !strings.contains(lower, "amd") &&
		!strings.contains(lower, "radeon") &&
		!strings.contains(lower, "gfx")
	nvidia: Perf_Clock
	rocm: Perf_Clock
	nvidia_note: string
	rocm_note: string
	if prefer_nvidia {
		nvidia, nvidia_note = nvidia_clock_probe()
		if nvidia.known {
			return nvidia, ""
		}
		rocm, rocm_note = rocm_clock_probe()
		if rocm.known {
			return rocm, ""
		}
	} else {
		rocm, rocm_note = rocm_clock_probe()
		if rocm.known {
			return rocm, ""
		}
		nvidia, nvidia_note = nvidia_clock_probe()
		if nvidia.known {
			return nvidia, ""
		}
	}
	warning := fmt.aprintf(
		"GPU clock unknown: nvidia-smi %s; rocm-smi %s",
		nvidia_note,
		rocm_note,
		allocator = allocator,
	)
	return {}, warning
}

@(private)
nvidia_clock_probe :: proc() -> (Perf_Clock, string) {
	state, stdout, stderr, exec_error := os.process_exec(
		{command = {"nvidia-smi", "--query-gpu=clocks.sm", "--format=csv,noheader,nounits"}},
		context.temp_allocator,
	)
	defer delete(stdout, context.temp_allocator)
	defer delete(stderr, context.temp_allocator)
	if exec_error != nil {
		return {}, fmt.tprintf("failed: %s", os.error_string(exec_error))
	}
	if state.exit_code != 0 {
		return {}, fmt.tprintf("exited %d", state.exit_code)
	}
	line := first_line(string(stdout))
	if mhz, ok := strconv.parse_int(line); ok && mhz > 0 {
		return {known = true, mhz = mhz, source = "nvidia-smi"}, ""
	}
	return {}, "reported no SM clock"
}

@(private)
rocm_clock_probe :: proc() -> (Perf_Clock, string) {
	state, stdout, stderr, exec_error := os.process_exec(
		{command = {"rocm-smi", "--showclocks"}},
		context.temp_allocator,
	)
	defer delete(stdout, context.temp_allocator)
	defer delete(stderr, context.temp_allocator)
	if exec_error != nil {
		return {}, fmt.tprintf("failed: %s", os.error_string(exec_error))
	}
	if state.exit_code != 0 {
		return {}, fmt.tprintf("exited %d", state.exit_code)
	}
	for line in strings.split_lines(string(stdout), context.temp_allocator) {
		lower := strings.to_lower(line, context.temp_allocator)
		index := strings.index(lower, "sclk")
		if index < 0 {
			continue
		}
		if mhz, ok := first_integer(line[index:]); ok && mhz > 0 {
			return {known = true, mhz = mhz, source = "rocm-smi"}, ""
		}
	}
	return {}, "reported no sclk line"
}

load_average_probe :: proc(allocator: mem.Allocator) -> (Perf_Load, string) {
	data, read_error := os.read_entire_file("/proc/loadavg", context.temp_allocator)
	if read_error != nil {
		return {}, fmt.aprintf("load average unknown: %v", read_error, allocator = allocator)
	}
	defer delete(data, context.temp_allocator)
	fields := strings.fields(string(data), context.temp_allocator)
	if len(fields) < 3 {
		return {}, fmt.aprintf(
			"load average unknown: /proc/loadavg did not parse",
			allocator = allocator,
		)
	}
	one, one_ok := strconv.parse_f64(fields[0])
	five, five_ok := strconv.parse_f64(fields[1])
	fifteen, fifteen_ok := strconv.parse_f64(fields[2])
	if !one_ok || !five_ok || !fifteen_ok {
		return {}, fmt.aprintf(
			"load average unknown: /proc/loadavg did not parse",
			allocator = allocator,
		)
	}
	return {available = true, one = one, five = five, fifteen = fifteen}, ""
}

@(private)
first_line :: proc(text: string) -> string {
	if index := strings.index_byte(text, '\n'); index >= 0 {
		return strings.trim_space(text[:index])
	}
	return strings.trim_space(text)
}

@(private)
first_integer :: proc(text: string) -> (int, bool) {
	start := -1
	for character, index in text {
		if character >= '0' && character <= '9' {
			if start < 0 {
				start = index
			}
			continue
		}
		if start >= 0 {
			if value, ok := strconv.parse_int(text[start:index]); ok {
				return value, true
			}
			start = -1
		}
	}
	if start >= 0 {
		return strconv.parse_int(text[start:])
	}
	return 0, false
}
