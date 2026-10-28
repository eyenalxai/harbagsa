#+vet explicit-allocators
package renderer

import "core:math"

import "src:ui"

// The 2D layer reads its colour, type, and spacing from here and nowhere else.
// Colours are authored as sRGB hex because that is what a person can reason
// about, and converted to linear once, because that is what the renderer blends
// in and what an sRGB attachment expects.
UI_REFERENCE_HEIGHT :: 720.0

UI_COLOR_TEXT_PRIMARY :: 0xEEF2F6
UI_COLOR_TEXT_SECONDARY :: 0xA7B2BF
UI_COLOR_TEXT_TERTIARY :: 0x818C99
UI_COLOR_ACCENT :: 0xE6AF3A
UI_COLOR_SURFACE_HUD :: 0x0F141A
UI_COLOR_SURFACE_MENU :: 0x151B23
UI_COLOR_SURFACE_RAISED :: 0x26313D
UI_COLOR_HAIRLINE :: 0xFFFFFF
UI_COLOR_SEPARATOR :: 0xFFFFFF
UI_COLOR_SLIDER_TRACK :: 0xFFFFFF
UI_COLOR_SCRIM :: 0x000000

UI_TEXT_SIZE_TITLE :: 21.0
UI_TEXT_SIZE_BODY :: 15.0
UI_TEXT_SIZE_CAPTION :: 14.0

UI_LEADING_TITLE :: 1.25
UI_LEADING_BODY :: 1.5
UI_LEADING_CAPTION :: 1.45

UI_TRACKING_TITLE :: -0.01
UI_TRACKING_CAPS :: 0.06

UI_MENU_MIN_WIDTH :: 200.0

Text_Type :: struct {
	size:        f32,
	line_height: f32,
	face:        Text_Face,
	weight:      f32,
	tracking:    f32,
	caps:        bool,
}

UI_Spacing :: ui.Spacing

UI_Theme :: struct {
	density: f32,
	hairline: f32,
	spacing: UI_Spacing,
	menu_min_width: f32,

	type_title:        Text_Type,
	type_body:         Text_Type,
	type_body_strong:  Text_Type,
	type_caption:      Text_Type,
	type_caption_caps: Text_Type,

	text_primary:   [4]f32,
	text_secondary: [4]f32,
	text_tertiary:  [4]f32,
	accent:         [4]f32,
	surface_hud:    [4]f32,
	surface_menu:   [4]f32,
	surface_raised: [4]f32,
	line_hairline:  [4]f32,
	line_separator: [4]f32,
	slider_track:   [4]f32,
	scrim:          [4]f32,
}

ui_theme_init :: proc(render_height: u32, base_weight: f32 = BASE_WEIGHT) -> UI_Theme {
	density := clamp(f32(render_height) / UI_REFERENCE_HEIGHT, 1.0, 2.0)
	weight := clamp(math.round(base_weight), MIN_WEIGHT, MAX_WEIGHT)
	strong := clamp(weight + 100, MIN_WEIGHT, MAX_WEIGHT)
	theme: UI_Theme
	// One device pixel, never a fraction of one: a half-pixel hairline resolves
	// to a two-pixel grey smear on a non-integer density.
	theme.density = density
	theme.hairline = max(1.0, math.round(density))

	theme.menu_min_width = UI_MENU_MIN_WIDTH * density

	theme.spacing = {
		xxs = 2.0 * density,
		xs  = 4.0 * density,
		sm  = 6.0 * density,
		md  = 8.0 * density,
		lg  = 12.0 * density,
		xl  = 16.0 * density,
		xxl = 24.0 * density,
	}

	theme.type_title = text_type(UI_TEXT_SIZE_TITLE, UI_LEADING_TITLE, .Sans, strong, UI_TRACKING_TITLE, density)
	theme.type_body = text_type(UI_TEXT_SIZE_BODY, UI_LEADING_BODY, .Sans, weight, 0, density)
	theme.type_body_strong = text_type(UI_TEXT_SIZE_BODY, UI_LEADING_BODY, .Sans, strong, 0, density)
	theme.type_caption = text_type(UI_TEXT_SIZE_CAPTION, UI_LEADING_CAPTION, .Sans, weight, 0, density)
	theme.type_caption_caps = text_type(
		UI_TEXT_SIZE_CAPTION,
		UI_LEADING_CAPTION,
		.Sans,
		strong,
		UI_TRACKING_CAPS,
		density,
	)
	theme.type_caption_caps.caps = true

	theme.text_primary = ui_color(UI_COLOR_TEXT_PRIMARY, 1.0)
	theme.text_secondary = ui_color(UI_COLOR_TEXT_SECONDARY, 1.0)
	theme.text_tertiary = ui_color(UI_COLOR_TEXT_TERTIARY, 1.0)
	theme.accent = ui_color(UI_COLOR_ACCENT, 1.0)
	theme.surface_hud = ui_color(UI_COLOR_SURFACE_HUD, 0.94)
	theme.surface_menu = ui_color(UI_COLOR_SURFACE_MENU, 1.0)
	theme.surface_raised = ui_color(UI_COLOR_SURFACE_RAISED, 1.0)
	theme.line_hairline = ui_color(UI_COLOR_HAIRLINE, 0.09)
	theme.line_separator = ui_color(UI_COLOR_SEPARATOR, 0.16)
	theme.slider_track = ui_color(UI_COLOR_SLIDER_TRACK, 0.20)
	theme.scrim = ui_color(UI_COLOR_SCRIM, 0.62)
	return theme
}

// A text size is an em in device pixels, rounded so it keys the rasterization
// atlas exactly. Leading multiplies the rounded size, so the line box and the
// glyphs share one unit.
text_type :: proc(
	size, leading: f32,
	face: Text_Face,
	weight: f32,
	tracking, density: f32,
) -> Text_Type {
	pixels := max(math.round(size * density), 1)
	return {
		size = pixels,
		line_height = pixels * leading,
		face = face,
		weight = weight,
		tracking = tracking,
	}
}

ui_color :: proc(hex: u32, alpha: f32) -> [4]f32 {
	return {
		srgb_to_linear(u8(hex >> 16)),
		srgb_to_linear(u8(hex >> 8)),
		srgb_to_linear(u8(hex)),
		alpha,
	}
}

srgb_to_linear :: proc(value: u8) -> f32 {
	channel := f32(value) / 255.0
	if channel <= 0.04045 {
		return channel / 12.92
	}
	return math.pow((channel + 0.055) / 1.055, 2.4)
}
