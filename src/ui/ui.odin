// The vocabulary the simulation and the renderer share. It holds data only, so
// the game never imports the renderer and the renderer never imports the game.
package ui

TYPE_WEIGHT_MIN :: f32(100)
TYPE_WEIGHT_MAX :: f32(900)
TYPE_WEIGHT_MONO_MAX :: f32(700)
TYPE_WEIGHT_DEFAULT :: f32(400)

Row_Kind :: enum {
	Setting,
	Action,
	Metric,
	Detail,
	Slider,
	Divider,
	Header,
	Spacer,
}

Row :: struct {
	kind:    Row_Kind,
	label:   string,
	value:   string,
	numeric: bool,
	ratio:   f32,
	ticks:   int,
}

Hint_Cell :: struct {
	keys:   string,
	action: string,
}

Menu :: struct {
	title:        string,
	rows:         []Row,
	selected:     int,
	hints:        []Hint_Cell,
	hint_columns: int,
	note:         string,
}

Hud :: struct {
	rows: []Row,
}
