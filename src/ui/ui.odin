// The vocabulary the simulation and the renderer share. It holds data only, so
// the game never imports the renderer and the renderer never imports the game.
package ui

Row_Kind :: enum {
	Setting,
	Action,
	Metric,
	Detail,
	Divider,
	Header,
	Spacer,
}

Row :: struct {
	kind:    Row_Kind,
	label:   string,
	value:   string,
	numeric: bool,
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
