package physics

import "core:math/linalg"
import rl "vendor:raylib"

CollisionMiss :: struct {}
CollisionHit :: struct {
	point:  [2]f32,
	normal: [2]f32,
	dist:   f32,
}
Collision :: union {
	CollisionMiss,
	CollisionHit,
}

raycast_aabb :: proc(origin, direction: [2]f32, rect: rl.Rectangle) -> Collision {
	near := ([2]f32{rect.x, rect.y} - origin) / direction
	far := ([2]f32{rect.x + rect.width, rect.y + rect.height} - origin) / direction

	if near.x > far.x {
		tmp := near.x
		near.x = far.x
		far.x = tmp
	}
	if near.y > far.y {
		tmp := near.y
		near.y = far.y
		far.y = tmp
	}

	if linalg.any(linalg.is_nan(far)) {
		return CollisionMiss{}
	}
	if linalg.any(linalg.is_nan(near)) {
		return CollisionMiss{}
	}

	if near.x > far.y || near.y > far.x {
		return CollisionMiss{}
	}

	near_hit := max(near.x, near.y)
	far_hit := min(far.x, far.y)
	if far_hit < 0 || near_hit > 1 {
		return CollisionMiss{}
	}

	point := origin + direction * near_hit
	normal := [2]f32{}
	if near.x > near.y {
		if direction.x < 0 {
			normal = {1, 0}
		} else {
			normal = {-1, 0}
		}
	} else {
		if direction.y < 0 {
			normal = {0, 1}
		} else {
			normal = {0, -1}
		}
	}

	return CollisionHit{point, normal, near_hit}
}

rect_vs_rect :: proc(r1, r2: rl.Rectangle, vel: [2]f32, dt: f32) -> Collision {
	half_extents := [2]f32{r1.width * 0.5, r1.height * 0.5}
	expanded_rect := rl.Rectangle {
		r2.x - half_extents.x,
		r2.y - half_extents.y,
		r2.width + r1.width,
		r2.height + r1.height,
	}
	return raycast_aabb({r1.x, r1.y} + half_extents, vel * dt, expanded_rect)
}
