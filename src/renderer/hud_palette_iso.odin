#+vet explicit-allocators
#+vet !unused-procedures // the frame tests read the face order and the fit
package renderer

import "core:math"

PALETTE_ISO_COS :: f32(0.8660254)
PALETTE_ISO_SIN :: f32(0.5)

Palette_Face :: enum {
	Right,
	Front,
	Top,
}

Palette_Quad :: struct {
	face:   Palette_Face,
	points: [4][2]f32,
	shade:  f32,
}

Palette_Box :: struct {
	faces: [3]Palette_Quad,
	count: int,
	min:   [2]f32,
	max:   [2]f32,
}

Palette_Transform :: struct {
	scale:  f32,
	offset: [2]f32,
}

PALETTE_FACE_INDICES := [3][4]int{
	{1, 3, 7, 5},
	{4, 6, 7, 5},
	{2, 3, 7, 6},
}


PALETTE_FACE_ORDER := [3]Palette_Face{.Right, .Front, .Top}
PALETTE_FACE_SHADES := [3]f32{0.78, 0.58, 1.0}

// The palette camera looks from (+x, +y, +z), so those three faces are the
// visible ones. The side faces come first; the top face is nearest.
palette_project_box :: proc(half_extents: [3]f32, base_pitch: f32) -> Palette_Box {
	box: Palette_Box
	if half_extents.x <= 0.0 || half_extents.y <= 0.0 || half_extents.z <= 0.0 {
		return box
	}

	cos_pitch := math.cos(base_pitch)
	sin_pitch := math.sin(base_pitch)
	corners: [8][2]f32
	for index in 0 ..< 8 {
		x := half_extents.x
		if (index & 1) == 0 {
			x = -x
		}
		y := half_extents.y
		if (index & 2) == 0 {
			y = -y
		}
		z := half_extents.z
		if (index & 4) == 0 {
			z = -z
		}
		corners[index] = palette_project_point(x, y, z, cos_pitch, sin_pitch)
	}

	box.min = corners[0]
	box.max = corners[0]
	for corner in corners {
		box.min.x = min(box.min.x, corner.x)
		box.min.y = min(box.min.y, corner.y)
		box.max.x = max(box.max.x, corner.x)
		box.max.y = max(box.max.y, corner.y)
	}

	for face_index in 0 ..< len(box.faces) {
		indices := PALETTE_FACE_INDICES[face_index]
		box.faces[face_index] = {
			face = PALETTE_FACE_ORDER[face_index],
			shade = PALETTE_FACE_SHADES[face_index],
		}
		for point_index in 0 ..< 4 {
			box.faces[face_index].points[point_index] = corners[indices[point_index]]
		}
	}
	box.count = len(box.faces)
	return box
}

palette_fit_transform :: proc(box: Palette_Box, rect: HUD_Rect) -> Palette_Transform {
	transform: Palette_Transform
	width := box.max.x - box.min.x
	height := box.max.y - box.min.y
	if box.count == 0 || width <= 0.0 || height <= 0.0 {
		return transform
	}
	if rect.width <= 0.0 || rect.height <= 0.0 {
		return transform
	}
	transform.scale = min(rect.width / width, rect.height / height)
	used := [2]f32{width * transform.scale, height * transform.scale}
	transform.offset = {
		rect.x + (rect.width - used.x) * 0.5 - box.min.x * transform.scale,
		rect.y + (rect.height - used.y) * 0.5 - box.min.y * transform.scale,
	}
	return transform
}

palette_transform_point :: proc(transform: Palette_Transform, point: [2]f32) -> [2]f32 {
	return {
		point.x * transform.scale + transform.offset.x,
		point.y * transform.scale + transform.offset.y,
	}
}

@(private)
palette_project_point :: proc(x, y, z, cos_pitch, sin_pitch: f32) -> [2]f32 {
	rotated_y := y * cos_pitch - z * sin_pitch
	rotated_z := y * sin_pitch + z * cos_pitch
	return {
		(x - rotated_z) * PALETTE_ISO_COS,
		(x + rotated_z) * PALETTE_ISO_SIN - rotated_y,
	}
}
