#+vet explicit-allocators
#+vet !unused-procedures // the agent harness calls this; the game binary does not
package game

import b3 "libs:box3d"

simulation_face :: proc(sim: ^Simulation, yaw, pitch: f32) {
	sim.player.yaw = b3.UnwindAngle(yaw)
	sim.player.pitch = clamp(pitch, -PITCH_LIMIT, PITCH_LIMIT)
}
