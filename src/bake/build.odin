#+vet explicit-allocators
#+vet !unused-procedures // the tool and a later runtime rebake share this
package bake

import "core:mem"
import "core:sys/info"
import "core:time"

MAX_THREADS :: 256

default_threads :: proc() -> (threads: int, ok: bool) {
	_, logical, counted := info.cpu_core_count()
	if !counted || logical < 1 {
		return 1, false
	}
	return clamp(logical, 1, MAX_THREADS), true
}

build :: proc(
	static: Static,
	options: Build_Options,
	allocator: mem.Allocator,
) -> (
	artifact: []u8,
	report: Build_Report,
	err: Build_Error,
) {
	if options.threads < 1 || options.threads > MAX_THREADS {
		return nil, {}, .Threads
	}
	if !quality_supported(options.quality) {
		return nil, {}, .Quality
	}
	if validation := static_supported(static); validation != .None {
		return nil, {}, validation
	}

	start := time.now()
	bvh, bvh_error := bvh_build(static, allocator)
	if bvh_error != .None {
		return nil, {}, bvh_error
	}
	defer bvh_destroy(&bvh, allocator)
	bvh_ms := u32(time.duration_milliseconds(time.since(start)))

	stage := time.now()
	lightmap, lightmap_error := lightmap_bake(
		static,
		&bvh,
		options.quality,
		options.threads,
		allocator,
	)
	if lightmap_error != .None {
		return nil, {}, lightmap_error
	}
	defer lightmap_destroy(&lightmap, allocator)
	lightmap_ms := u32(time.duration_milliseconds(time.since(stage)))

	stage = time.now()
	probes, probe_error := probe_bake(static, &bvh, options.quality, options.threads, allocator)
	if probe_error != .None {
		return nil, {}, probe_error
	}
	defer probe_destroy(&probes, allocator)
	probe_ms := u32(time.duration_milliseconds(time.since(stage)))

	bake_ms := u32(time.duration_milliseconds(time.since(start)))
	report = {
		boxes          = len(static.boxes),
		lights         = len(static.lights),
		charts         = len(lightmap.layout.charts),
		probes         = len(probes.states),
		atlas_size     = int(options.quality.atlas_size),
		valid_texels   = lightmap.valid_texels,
		invalid_texels = lightmap.invalid_texels,
		dilated_texels = lightmap.dilated_texels,
		lightmap_rays  = lightmap.rays,
		probe_rays     = probes.rays,
		shadow_rays    = lightmap.shadow_rays + probes.shadow_rays,
		invalid_probes = probes.invalid_probes,
		dilated_probes = probes.dilated_probes,
		atlas_bytes    = len(lightmap.atlas),
		probe_bytes    = len(probes.irradiance) + len(probes.moments) +
			len(probes.states) * size_of(Probe_State),
		bake_ms        = bake_ms,
		bvh_ms         = bvh_ms,
		lightmap_ms    = lightmap_ms,
		probe_ms       = probe_ms,
		key            = key(static, options.quality),
	}
	stats := Stats {
		// Wall time is telemetry, not bake data: a thread-count or machine
		// difference must not change the artifact bytes. The tool prints the
		// measured time, and the runtime reports the stored value.
		bake_ms        = 0,
		lightmap_rays  = lightmap.rays,
		probe_rays     = probes.rays,
		atlas_texels   = options.quality.atlas_size * options.quality.atlas_size,
		probe_count    = u32(len(probes.states)),
		invalid_texels = u32(lightmap.invalid_texels),
		invalid_probes = u32(probes.invalid_probes),
	}
	payload_hash: u64
	encode_start := time.now()
	artifact, payload_hash, err = encode_artifact(
		{
			key = report.key,
			quality = options.quality,
			stats = stats,
			faces = lightmap.layout.faces,
			slots = lightmap.layout.slots,
			probe_states = probes.states,
			probe_min = probes.min,
			probe_spacing = probes.spacing,
			probe_counts = probes.counts,
			probe_texels = u32(PROBE_TEXELS),
			probe_columns = probes.columns,
			atlas = lightmap.atlas,
			probe_irradiance = probes.irradiance,
			probe_moments = probes.moments,
		},
		allocator,
	)
	if err != .None {
		return nil, {}, err
	}
	report.encode_ms = u32(time.duration_milliseconds(time.since(encode_start)))
	report.artifact_bytes = len(artifact)
	report.payload_hash = payload_hash
	return artifact, report, .None
}

@(private)
static_supported :: proc(static: Static) -> Build_Error {
	if len(static.boxes) == 0 {
		return .No_Static_Boxes
	}
	for entry in static.boxes {
		box := entry.box
		if !vec3_finite(box.center) || !vec3_finite(box.half_extents) {
			return .Bad_Box
		}
		if box.half_extents.x <= 0 || box.half_extents.y <= 0 || box.half_extents.z <= 0 {
			return .Bad_Box
		}
		if !vec3_finite({box.color.x, box.color.y, box.color.z}) ||
		   !vec3_finite({box.rotation.x, box.rotation.y, box.rotation.z}) {
			return .Bad_Box
		}
		if !finite_f64(f64(box.rotation.w)) || !finite_f64(f64(box.emissive)) || box.emissive < 0 {
			return .Bad_Box
		}
	}
	for light in static.lights {
		if !vec3_finite(light.position) || !vec3_finite(light.color) {
			return .Bad_Light
		}
		if !finite_f64(f64(light.intensity)) || light.intensity < 0 ||
		   !finite_f64(f64(light.range)) || light.range <= 0 ||
		   !finite_f64(f64(light.emissive)) || light.emissive < 0 {
			return .Bad_Light
		}
	}
	return .None
}

@(private)
vec3_finite :: proc(value: [3]f32) -> bool {
	return finite_f64(f64(value.x)) && finite_f64(f64(value.y)) && finite_f64(f64(value.z))
}
