#+vet explicit-allocators
package bake

import "core:math"

// The nine real SH basis functions in the order the texture stores them. The
// coefficients reconstruct the same lightmap-scale value the octa path stores,
// so probes and the lightmap share one brightness scale.
@(private)
sh_basis :: proc(index: int, direction: DVec3) -> f64 {
	switch index {
	case 0:
		return 0.28209479177387814
	case 1:
		return 0.48860251190291992 * direction.y
	case 2:
		return 0.48860251190291992 * direction.z
	case 3:
		return 0.48860251190291992 * direction.x
	case 4:
		return 1.0925484305920792 * direction.x * direction.y
	case 5:
		return 1.0925484305920792 * direction.y * direction.z
	case 6:
		return 0.31539156525252005 * (3.0 * direction.z * direction.z - 1.0)
	case 7:
		return 1.0925484305920792 * direction.x * direction.z
	case 8:
		return 0.54627421529603959 * (direction.x * direction.x - direction.y * direction.y)
	}
	return 0
}

@(private)
sh_band :: proc(index: int) -> int {
	if index == 0 {
		return 0
	}
	if index <= 3 {
		return 1
	}
	return 2
}

@(private)
sh_band_scale :: proc(band: int) -> f64 {
	switch band {
	case 0:
		return 1.0
	case 1:
		return 2.0 / 3.0
	}
	return 0.25
}

// Lanczos sigma factors over three bands. The clamped-cosine reconstruction has
// a 1/16 back lobe; the window trades a little directional contrast for less
// ringing from the bright emitter that no amount of depth testing can remove.
@(private)
sh_window :: proc(index: int) -> f64 {
	band := f64(sh_band(index))
	if band == 0 {
		return 1.0
	}
	angle := math.PI * band / 3.0
	return math.sin(angle) / angle
}

@(private)
probe_blend_sh9 :: proc(
	work: ^Probe_Work,
	probe: int,
	directions: []DVec3,
	radiance: []DVec3,
) #no_bounds_check {
	sums: [PROBE_SH_COEFFS][3]f64
	for ray_index in 0 ..< work.rays {
		value := radiance[ray_index]
		for index in 0 ..< PROBE_SH_COEFFS {
			weight := sh_basis(index, directions[ray_index])
			sums[index].x += value.x * weight
			sums[index].y += value.y * weight
			sums[index].z += value.z * weight
		}
	}
	projection := 4.0 * math.PI / f64(work.rays)
	for index in 0 ..< PROBE_SH_COEFFS {
		scale := projection * sh_band_scale(sh_band(index)) * sh_window(index)
		base := probe * PROBE_SH_TEXELS + index * 3
		work.irradiance_f16[base + 0] = f16(sums[index].x * scale)
		work.irradiance_f16[base + 1] = f16(sums[index].y * scale)
		work.irradiance_f16[base + 2] = f16(sums[index].z * scale)
	}
}
