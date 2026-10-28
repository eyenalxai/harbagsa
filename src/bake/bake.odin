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

Input :: struct {
	boxes:   []Box_Entry,
	lights:  []Light_Entry,
	quality: Quality,
}
