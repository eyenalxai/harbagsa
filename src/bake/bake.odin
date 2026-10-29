#+vet explicit-allocators
#+vet !unused-procedures // the frame and the renderer share this package
package bake

import "src:geometry"

FORMAT_VERSION :: 1
TOOL_VERSION :: 1

// The bake key mixes this version too, so a changed input rule invalidates an
// old artifact without a format bump.
KEY_VERSION :: 1

MAGIC :: [4]u8{'H', 'B', 'A', 'K'}

ATLAS_SIZE :: 1024
ATLAS_BYTES_PER_TEXEL :: 8
TEXELS_PER_METER :: 4
GUTTER_TEXELS :: 4
MIN_CHART_TEXELS :: 8

PROBE_TEXELS :: 8
PROBE_TEXEL_COUNT :: PROBE_TEXELS * PROBE_TEXELS
PROBE_BYTES_PER_IRRADIANCE_TEXEL :: 8
PROBE_BYTES_PER_MOMENT_TEXEL :: 4
PROBE_SPACING :: 1.0
PROBE_SPACING_FALLBACK :: 2.0

LIGHTMAP_RAYS :: 128
PROBE_RAYS :: 1024
BOUNCES :: 1

// A probe shelf atlas must stay inside the minimum Vulkan 2D extent.
MAX_PROBE_ATLAS_DIM :: 16384

Quality :: struct #packed {
	atlas_size:       u32,
	texels_per_meter: u32,
	gutter_texels:    u32,
	min_chart:        u32,
	lightmap_rays:    u32,
	probe_rays:       u32,
	bounces:          u32,
	probe_spacing:    f32,
	probe_texels:     u32,
}

DEFAULT_QUALITY :: Quality {
	atlas_size       = ATLAS_SIZE,
	texels_per_meter = TEXELS_PER_METER,
	gutter_texels    = GUTTER_TEXELS,
	min_chart        = MIN_CHART_TEXELS,
	lightmap_rays    = LIGHTMAP_RAYS,
	probe_rays       = PROBE_RAYS,
	bounces          = BOUNCES,
	probe_spacing    = PROBE_SPACING,
	probe_texels     = PROBE_TEXELS,
}

Box_Source :: enum u8 {
	Arena,
	Placed,
}

// The bake input is canonical: arena boxes in array order, then placed static
// boxes by object id. `id` is the arena index or the placed object id.
Box_Entry :: struct {
	source: Box_Source,
	id:     u32,
	box:    geometry.Box,
}

Light_Entry :: struct {
	id:        u32,
	position:  [3]f32,
	color:     [3]f32,
	intensity: f32,
	range:     f32,
	emissive:  f32,
}

// The static input is canonical: arena boxes in array order, then placed static
// boxes by object id. `id` is the arena index or the placed object id.
Static :: struct {
	boxes:  []Box_Entry,
	lights: []Light_Entry,
}

// A fixed seed is part of the tool version. The artifact must not depend on a
// clock, an environment variable, or a thread count.
SEED :: u64(0x4842414b45534545)

SURFACE_PUSHOFF :: f64(0.005)
PROBE_OFFSET_MARGIN :: f64(0.02)
PROBE_OFFSET_MAX_FRACTION :: f64(0.5)
RAY_ORIGIN_BIAS :: f64(0.002)
SHADOW_END_BIAS :: f64(0.001)
RAY_TMIN :: f64(0.001)
RAY_MAX :: f64(100.0)

PROBE_IRRADIANCE_GAMMA :: f64(5.0)

PROBE_MIN :: [3]f32{-20.0, 0.0, -20.0}
PROBE_COUNTS :: [3]u32{40, 5, 40}
PROBE_MIN_FALLBACK :: [3]f32{-20.0, -0.5, -20.0}
PROBE_COUNTS_FALLBACK :: [3]u32{20, 3, 20}

// Probes sit at cell centers, so the 1 m grid samples y = 0.5 ... 4.5 and the
// 2 m fallback samples the same heights.
probe_grid :: proc(spacing: f32) -> (min: [3]f32, counts: [3]u32) {
	if spacing == PROBE_SPACING_FALLBACK {
		return PROBE_MIN_FALLBACK, PROBE_COUNTS_FALLBACK
	}
	return PROBE_MIN, PROBE_COUNTS
}

Build_Options :: struct {
	quality: Quality,
	threads: int,
}

Build_Error :: enum {
	None,
	No_Static_Boxes,
	Bad_Box,
	Bad_Light,
	Atlas_Full,
	Probe_Count,
	Threads,
	Quality,
	Artifact,
}

build_error_name :: proc(err: Build_Error) -> string {
	switch err {
	case .None:
		return "none"
	case .No_Static_Boxes:
		return "no static boxes"
	case .Bad_Box:
		return "bad static box"
	case .Bad_Light:
		return "bad static light"
	case .Atlas_Full:
		return "the lightmap atlas is full"
	case .Probe_Count:
		return "the probe volume is invalid"
	case .Threads:
		return "invalid thread count"
	case .Quality:
		return "the bake quality is not supported by the format"
	case .Artifact:
		return "the artifact layout does not match the input"
	}
	return "unknown bake error"
}

Build_Report :: struct {
	boxes:          int,
	lights:         int,
	charts:         int,
	probes:         int,
	atlas_size:     int,
	valid_texels:   int,
	invalid_texels: int,
	dilated_texels: int,
	lightmap_rays:  u64,
	probe_rays:     u64,
	shadow_rays:    u64,
	invalid_probes: int,
	atlas_bytes:    int,
	probe_bytes:    int,
	artifact_bytes: int,
	bake_ms:        u32,
	bvh_ms:         u32,
	lightmap_ms:    u32,
	probe_ms:       u32,
	encode_ms:      u32,
	key:            u64,
	payload_hash:   u64,
}
