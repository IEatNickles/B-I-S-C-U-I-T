package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:slice"
import "core:sort"
import "core:strconv"
import "core:strings"
import "core:unicode"
import rl "vendor:raylib"

Player :: struct {
	pos:        [2]f32,
	vel:        [2]f32,
	size:       f32,
	speed:      f32,
	jump_force: f32,
	grounded:   bool,
}

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

TileSide :: enum {
	Top,
	Bottom,
	Left,
	Right,
	Center,
	None,
}

BasicTile :: struct {
	pos:  [2]f32,
	size: [2]f32,
	side: TileSide,
}

DeathTile :: struct {
	pos:  [2]f32,
	size: [2]f32,
}

Tile :: union {
	BasicTile,
	DeathTile,
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

rects_intersect :: proc(r1, r2: rl.Rectangle) -> bool {
	return(
		(r1.x + r1.width > r2.x || r2.x + r2.width > r1.x) &&
		(r1.y + r1.height > r2.y || r2.y + r2.height > r1.y) \
	)
}

main :: proc() {
	rl.InitWindow(1600, 900, "B I S C U I T")
	rl.SetTargetFPS(60)

	floor_tex := rl.LoadTexture("assets/kenny/PNG/Tiles/Brown tiles/tileBrown_27.png")
	floor_top_tex := rl.LoadTexture("assets/kenny/PNG/Tiles/Brown tiles/tileBrown_02.png")
	floor_bot_tex := rl.LoadTexture("assets/kenny/PNG/Tiles/Brown tiles/tileBrown_27.png")
	floor_lef_tex := rl.LoadTexture("assets/kenny/PNG/Tiles/Brown tiles/tileBrown_01.png")
	floor_rig_tex := rl.LoadTexture("assets/kenny/PNG/Tiles/Brown tiles/tileBrown_03.png")
	floor_cen_tex := rl.LoadTexture("assets/kenny/PNG/Tiles/Brown tiles/tileBrown_04.png")
	spike_tex := rl.LoadTexture("assets/kenny/PNG/Other/spikesHigh.png")
	player_tex := rl.LoadTexture("assets/kenny/PNG/Players/Player Green/playerGreen_stand.png")
	player_walk1_tex := rl.LoadTexture(
		"assets/kenny/PNG/Players/Player Green/playerGreen_walk1.png",
	)
	player_walk2_tex := rl.LoadTexture(
		"assets/kenny/PNG/Players/Player Green/playerGreen_walk3.png",
	)
	player_air_tex := rl.LoadTexture("assets/kenny/PNG/Players/Player Green/playerGreen_up2.png")

	spawn_point := [2]f32{math.nan_f32(), math.nan_f32()}

	data, success := os.read_entire_file("assets/level.txt")
	if !success {
		fmt.println("File no good :(")
	}

	level: [dynamic]Tile
	i := -1
	for b in data {
		if strings.is_ascii_space(rune(b)) {
			continue
		}
		num := u8(b) - u8('0')
		i += 1

		if num == 0 {
			continue
		}
		pos := [2]f32{f32(i % 32), math.floor(f32(i) / 32)} * 50
		if num == 3 {
			assert(
				linalg.all(linalg.is_nan(spawn_point)),
				"Cannot have more than one spawn point in a level",
			)
			spawn_point = pos + {25, 25}
		}

		switch num {
		case 1:
			append(&level, BasicTile{pos, {50, 50}, .None})
		case 4:
			append(&level, BasicTile{pos, {50, 50}, .Top})
		case 5:
			append(&level, BasicTile{pos, {50, 50}, .Bottom})
		case 6:
			append(&level, BasicTile{pos, {50, 50}, .Left})
		case 7:
			append(&level, BasicTile{pos, {50, 50}, .Right})
		case 8:
			append(&level, BasicTile{pos, {50, 50}, .Center})
		case 2:
			append(&level, DeathTile{pos, {50, 50}})
		}
	}

	plr := Player{spawn_point, {}, 20, 10, 20, false}
	input_dir: f32

	cam := rl.Camera2D{{}, {}, 0, 1}
	dt: f32 = 0
	for !rl.WindowShouldClose() {
		dt = rl.GetFrameTime()

		if rl.IsKeyDown(rl.KeyboardKey.D) {
			input_dir = 1
		} else if rl.IsKeyDown(rl.KeyboardKey.A) {
			input_dir = -1
		} else {
			input_dir = 0
		}
		plr.vel.x = math.lerp(plr.vel.x, input_dir * plr.speed * 100, dt * 20)
		plr.vel.y += 200
		if (rl.IsKeyPressed(rl.KeyboardKey.W)) {
			plr.vel.y = plr.jump_force * -100
		}

		plr_rect := rl.Rectangle {
			plr.pos.x - plr.size,
			plr.pos.y - plr.size * 1.3,
			plr.size * 2,
			plr.size * 2 * 1.3,
		}

		vel_rect := rl.Rectangle {
			plr_rect.x + plr.vel.x * dt,
			plr_rect.y + plr.vel.y * dt,
			plr_rect.width,
			plr_rect.height,
		}

		test_rect := rl.Rectangle {
			min(plr_rect.x, vel_rect.x),
			min(plr_rect.y, vel_rect.y),
			plr_rect.width + abs(plr.vel.x) * dt,
			plr_rect.height + abs(plr.vel.y) * dt,
		}

		HitEntry :: struct {
			idx:  int,
			dist: f32,
		}
		hits: [dynamic]HitEntry
		for tile, i in level {
			switch t in tile {
			case BasicTile:
				tile_rect := rl.Rectangle{t.pos.x, t.pos.y, t.size.x, t.size.y}
				if !rects_intersect(tile_rect, test_rect) {
					continue
				}

				switch col in rect_vs_rect(plr_rect, tile_rect, plr.vel, dt) {
				case CollisionHit:
					append(&hits, HitEntry{i, col.dist})
					if col.normal.y < 0 {
						plr.grounded = true
					}
				case CollisionMiss:
				}
			case DeathTile:
				tile_rect := rl.Rectangle{t.pos.x, t.pos.y, t.size.x, t.size.y}
				if !rects_intersect(tile_rect, test_rect) {
					continue
				}

				switch col in rect_vs_rect(plr_rect, tile_rect, plr.vel, dt) {
				case CollisionHit:
					plr.pos = spawn_point
					plr.vel = {0, 0}
				case CollisionMiss:
				}
			}
		}

		slice.sort_by(hits[:], proc(a, b: HitEntry) -> bool {
			return a.dist < b.dist
		})

		for hit in hits {
			t := level[hit.idx].(BasicTile)
			tile_rect := rl.Rectangle{t.pos.x, t.pos.y, t.size.x, t.size.y}
			switch col in rect_vs_rect(plr_rect, tile_rect, plr.vel, dt) {
			case CollisionHit:
				plr.vel += col.normal * linalg.abs(plr.vel) * (1.001 - col.dist)
			case CollisionMiss:
			}
		}

		plr.pos += plr.vel * dt

		rl.BeginDrawing()

		rl.ClearBackground(rl.BROWN)

		rl.BeginMode2D(cam)

		for tile in level {
			switch t in tile {
			case BasicTile:
				tex: rl.Texture2D
				switch t.side {
				case .Top:
					tex = floor_top_tex
				case .Center:
					tex = floor_cen_tex
				case .Left:
					tex = floor_lef_tex
				case .Right:
					tex = floor_rig_tex
				case .Bottom:
					tex = floor_bot_tex
				case .None:
					tex = floor_tex
				}
				rl.DrawTexturePro(
					tex,
					rl.Rectangle{0, 0, 64, 64},
					rl.Rectangle{t.pos.x, t.pos.y, 50, 50},
					{0, 0},
					0,
					rl.WHITE,
				)
			case DeathTile:
				rl.DrawTexturePro(
					spike_tex,
					rl.Rectangle{0, 0, 64, 30},
					rl.Rectangle{t.pos.x, t.pos.y, 50, 50},
					{0, 0},
					0,
					rl.WHITE,
				)
			}
		}
		rl.DrawCircleV(spawn_point, 30, rl.YELLOW)
		// rl.DrawCircleV(plr.pos, plr.size, rl.SKYBLUE)
		tex: rl.Texture2D
		if plr.grounded {
			if abs(input_dir) > 0 {
				tex = i32(rl.GetTime() * 10) % 2 == 0 ? player_walk1_tex : player_walk2_tex
			} else {
				tex = player_tex
			}
		} else {
			tex = player_air_tex
		}
		rl.DrawTexturePro(
			tex,
			rl.Rectangle{0, 0, 38 * (input_dir == 0 ? 1 : input_dir), 50},
			plr_rect,
			{},
			0,
			rl.WHITE,
		)

		rl.EndMode2D()

		rl.DrawFPS(0, 0)

		rl.EndDrawing()

		plr.grounded = false
	}

	rl.CloseWindow()
}
