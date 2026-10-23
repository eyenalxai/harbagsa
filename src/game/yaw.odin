#+vet explicit-allocators
package game

import "core:math"

import b3 "libs:box3d"

yaw_forward_horizontal :: proc(yaw: f32) -> b3.Vec3 {
	return {-math.sin(yaw), 0.0, -math.cos(yaw)}
}

yaw_right :: proc(yaw: f32) -> b3.Vec3 {
	return {math.cos(yaw), 0.0, -math.sin(yaw)}
}
