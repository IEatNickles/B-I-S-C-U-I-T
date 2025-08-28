package main

import "core:encoding/json"
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

import "physics"

Player :: struct {
	pos:        [2]f32,
	vel:        [2]f32,
	size:       [2]f32,
	speed:      f32,
	jump_force: f32,
	grounded:   bool,
	checkpoint: [2]f32,
	jumps:      i32,
	input:      f32,
	dir:        f32,
	walk_time:  i32,
}

TileSide :: enum {
	Top,
	Left,
	Right,
	Center,
	None,
}

Direction :: enum {
	Up,
	Down,
	Left,
	Right,
}

BasicTile :: struct {
	pos:  [2]f32,
	side: TileSide,
}

DeathTile :: struct {
	pos: [2]f32,
	dir: Direction,
}

CheckpointTile :: struct {
	pos: [2]f32,
}

EndTile :: struct {
	pos: [2]f32,
}

TILE_SIZE :: 50

Tile :: union {
	BasicTile,
	DeathTile,
	CheckpointTile,
	EndTile,
}

rects_intersect :: proc(r1, r2: rl.Rectangle) -> bool {
	return(
		(r1.x + r1.width > r2.x || r2.x + r2.width > r1.x) &&
		(r1.y + r1.height > r2.y || r2.y + r2.height > r1.y) \
	)
}

Level :: struct {
	tiles: []Tile,
	start: [2]f32,
	size:  [2]i32,
}

Assets :: struct {
	floor_tex:        rl.Texture2D,
	floor_top_tex:    rl.Texture2D,
	floor_lef_tex:    rl.Texture2D,
	floor_rig_tex:    rl.Texture2D,
	floor_cen_tex:    rl.Texture2D,
	spike_tex:        rl.Texture2D,
	checkpoint_tex:   rl.Texture2D,
	start_tex:        rl.Texture2D,
	end_tex:          rl.Texture2D,
	player_tex:       rl.Texture2D,
	jump_sound:       rl.Sound,
	jump_fail_sound:  rl.Sound,
	checkpoint_sound: rl.Sound,
	finish_sound:     rl.Sound,
	walk_sound:       rl.Sound,
	death_sound:      rl.Sound,
}

main :: proc() {
	rl.InitWindow(1600, 900, "B I S C U I T")
	rl.InitAudioDevice()
	rl.SetTargetFPS(60)

	assets := load_assets("assets")
	levels := load_levels("assets/levels")

	current_level := 0
	level := levels[current_level]

	plr: Player
	plr.pos = level.start
	plr.size = {17, 33}
	plr.speed = 7
	plr.jump_force = 12
	plr.checkpoint = plr.pos
	plr.jumps = 2
	plr.dir = 1

	play_walk: bool
	walk_time: i32

	cam := rl.Camera2D{{}, {}, 0, 1}
	dt: f32 = 0
	for !rl.WindowShouldClose() {
		dt = rl.GetFrameTime()

		cam.target = linalg.lerp(
			cam.target,
			linalg.floor(plr.pos / {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}) * 1600,
			dt * 4,
		)

		if rl.IsKeyDown(rl.KeyboardKey.D) {
			plr.input = 1
			plr.dir = 1
		} else if rl.IsKeyDown(rl.KeyboardKey.A) {
			plr.input = -1
			plr.dir = -1
		} else {
			plr.input = 0
		}
		plr.vel.x = math.lerp(plr.vel.x, plr.input * plr.speed * 100, dt * 20)
		if plr.vel.x < 1 && plr.vel.x > 0 {
			plr.vel.x = 0
		}
		plr.vel.y += 100
		if (rl.IsKeyPressed(rl.KeyboardKey.W)) {
			if plr.jumps > 0 {
				plr.vel.y = plr.jump_force * -100
				plr.jumps -= 1
				rl.PlaySound(assets.jump_sound)
			} else {
				rl.PlaySound(assets.jump_fail_sound)
			}
		}

		plr_rect := rl.Rectangle{plr.pos.x, plr.pos.y, plr.size.x, plr.size.y}

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
		for tile, i in level.tiles {
			switch t in tile {
			case BasicTile:
				tile_rect := rl.Rectangle{t.pos.x, t.pos.y, TILE_SIZE, TILE_SIZE}
				if !rects_intersect(tile_rect, test_rect) {
					continue
				}

				switch col in physics.rect_vs_rect(plr_rect, tile_rect, plr.vel, dt) {
				case physics.CollisionHit:
					append(&hits, HitEntry{i, col.dist})
					if col.normal.y < 0 {
						plr.jumps = 2
						plr.grounded = true
					}
				case physics.CollisionMiss:
				}
			case DeathTile:
				tile_rect := rl.Rectangle{t.pos.x, t.pos.y, TILE_SIZE, TILE_SIZE}
				if !rects_intersect(tile_rect, test_rect) {
					continue
				}

				switch col in physics.rect_vs_rect(plr_rect, tile_rect, plr.vel, dt) {
				case physics.CollisionHit:
					plr.pos = plr.checkpoint
					plr.vel = {0, 0}
					rl.PlaySound(assets.death_sound)
				case physics.CollisionMiss:
				}
			case CheckpointTile:
				tile_rect := rl.Rectangle{t.pos.x, t.pos.y, TILE_SIZE, TILE_SIZE}
				if !rects_intersect(tile_rect, test_rect) {
					continue
				}

				switch col in physics.rect_vs_rect(plr_rect, tile_rect, plr.vel, dt) {
				case physics.CollisionHit:
					if plr.checkpoint != t.pos {
						plr.checkpoint = t.pos
						rl.PlaySound(assets.checkpoint_sound)
					}
				case physics.CollisionMiss:
				}
			case EndTile:
				tile_rect := rl.Rectangle{t.pos.x, t.pos.y, TILE_SIZE, TILE_SIZE}
				if !rects_intersect(tile_rect, test_rect) {
					continue
				}

				switch col in physics.rect_vs_rect(plr_rect, tile_rect, plr.vel, dt) {
				case physics.CollisionHit:
					current_level += 1
					level = levels[current_level]
					plr.checkpoint = level.start
					plr.pos = level.start
					plr.vel = {}
					rl.PlaySound(assets.finish_sound)
				case physics.CollisionMiss:
				}
			}
		}

		slice.sort_by(hits[:], proc(a, b: HitEntry) -> bool {
			return a.dist < b.dist
		})

		for hit in hits {
			t := level.tiles[hit.idx].(BasicTile)
			tile_rect := rl.Rectangle{t.pos.x, t.pos.y, TILE_SIZE, TILE_SIZE}
			switch col in physics.rect_vs_rect(plr_rect, tile_rect, plr.vel, dt) {
			case physics.CollisionHit:
				plr.vel += col.normal * linalg.abs(plr.vel) * (1.001 - col.dist)
			case physics.CollisionMiss:
			}
		}

		plr.pos += plr.vel * dt

		rl.BeginDrawing()

		rl.ClearBackground(rl.BROWN)

		rl.BeginMode2D(cam)

		draw_level(level, assets)
		draw_player(&plr, assets)

		rl.EndMode2D()

		rl.DrawFPS(0, 0)

		rl.EndDrawing()

		plr.grounded = false
	}

	rl.CloseWindow()
}

load_levels :: proc(path: string) -> []Level {
	levels: [dynamic]Level
	level_dir, err0 := os.open(path)
	if err0 != os.ERROR_NONE {
		fmt.eprintln("Could not open directory: ", err0)
	} else {
		defer os.close(level_dir)
		file_infos, err1 := os.read_dir(level_dir, -1)
		if err1 != os.ERROR_NONE {
			fmt.eprintln("Could not read files: ", err1)
		} else {
			for file in file_infos {
				level: Level
				i := -1

				content, err2 := os.read_entire_file(file.fullpath)
				if !err2 {
					fmt.eprintln("File no good :(")
				}
				j, e := json.parse(content)
				#partial switch lvl in j {
				case json.Object:
					size := lvl["size"].(json.Array)
					level.size.x = i32(size[0].(json.Float))
					level.size.y = i32(size[1].(json.Float))
					level.tiles = make([]Tile, level.size.x * level.size.y)
					data := lvl["data"].(json.String)
					for b in data {
						i += 1
						pos :=
							[2]f32 {
								f32(i % int(level.size.x)),
								math.floor(f32(i) / f32(level.size.x)),
							} *
							50
						switch b {
						case '0':
							continue
						case 'B':
							level.tiles[i] = BasicTile{pos, .None}
						case 'T':
							level.tiles[i] = BasicTile{pos, .Top}
						case 'L':
							level.tiles[i] = BasicTile{pos, .Left}
						case 'R':
							level.tiles[i] = BasicTile{pos, .Right}
						case 'C':
							level.tiles[i] = BasicTile{pos, .Center}
						case 'D':
							level.tiles[i] = DeathTile{pos, .Up}
						case 'F':
							level.tiles[i] = DeathTile{pos, .Down}
						case 'Q':
							level.tiles[i] = DeathTile{pos, .Left}
						case 'W':
							level.tiles[i] = DeathTile{pos, .Right}
						case 'P':
							level.tiles[i] = CheckpointTile{pos}
						case 'S':
							level.start = pos
						case 'E':
							level.tiles[i] = EndTile{pos}
						}
					}
				case:
					fmt.eprintln("Expected an object")
				}

				append(&levels, level)
				fmt.println("loaded level: ", file.name)
			}
		}
	}
	return levels[:]
}

load_assets :: proc(path: string) -> (assets: Assets) {
	assets.floor_tex = rl.LoadTexture("assets/textures/rock.png")
	assets.floor_top_tex = rl.LoadTexture("assets/textures/rock_top.png")
	assets.floor_lef_tex = rl.LoadTexture("assets/textures/rock_left.png")
	assets.floor_rig_tex = rl.LoadTexture("assets/textures/rock_right.png")
	assets.floor_cen_tex = rl.LoadTexture("assets/textures/rock_center.png")
	assets.spike_tex = rl.LoadTexture("assets/textures/spike.png")
	assets.checkpoint_tex = rl.LoadTexture("assets/textures/flag_up.png")
	assets.start_tex = rl.LoadTexture("assets/kenny/PNG/Other/doorRed_top.png")
	assets.end_tex = rl.LoadTexture("assets/textures/biscuit.png")
	assets.player_tex = rl.LoadTexture("assets/textures/player.png")

	assets.jump_sound = rl.LoadSound("assets/sounds/jump.wav")
	assets.jump_fail_sound = rl.LoadSound("assets/sounds/jump_fail.wav")
	assets.checkpoint_sound = rl.LoadSound("assets/sounds/checkpoint.wav")
	assets.finish_sound = rl.LoadSound("assets/sounds/finish.wav")
	assets.walk_sound = rl.LoadSound("assets/sounds/walk.wav")
	assets.death_sound = rl.LoadSound("assets/sounds/death.wav")
	return assets
}

draw_level :: proc(level: Level, assets: Assets) {
	for tile in level.tiles {
		switch t in tile {
		case BasicTile:
			tex: rl.Texture2D
			switch t.side {
			case .Top:
				tex = assets.floor_top_tex
			case .Center:
				tex = assets.floor_cen_tex
			case .Left:
				tex = assets.floor_lef_tex
			case .Right:
				tex = assets.floor_rig_tex
			case .None:
				tex = assets.floor_tex
			}
			rl.DrawTexturePro(
				tex,
				rl.Rectangle{0, 0, 32, 32},
				rl.Rectangle{t.pos.x, t.pos.y, 50, 50},
				{0, 0},
				0,
				rl.WHITE,
			)
		case DeathTile:
			switch t.dir {
			case .Up:
				rl.DrawTexturePro(
					assets.spike_tex,
					rl.Rectangle{0, 0, 32, 32},
					rl.Rectangle{t.pos.x, t.pos.y, 50, 50},
					{},
					0,
					rl.WHITE,
				)
			case .Down:
				rl.DrawTexturePro(
					assets.spike_tex,
					rl.Rectangle{0, 0, 32, 32},
					rl.Rectangle{t.pos.x + 50, t.pos.y + 50, 50, 50},
					{},
					180,
					rl.WHITE,
				)
			case .Left:
				rl.DrawTexturePro(
					assets.spike_tex,
					rl.Rectangle{0, 0, 32, 32},
					rl.Rectangle{t.pos.x, t.pos.y + 50, 50, 50},
					{},
					270,
					rl.WHITE,
				)
			case .Right:
				rl.DrawTexturePro(
					assets.spike_tex,
					rl.Rectangle{0, 0, 32, 32},
					rl.Rectangle{t.pos.x + 50, t.pos.y, 50, 50},
					{},
					90,
					rl.WHITE,
				)
			}
		case CheckpointTile:
			rl.DrawTexturePro(
				assets.checkpoint_tex,
				rl.Rectangle{0, 0, 32, 32},
				rl.Rectangle{t.pos.x, t.pos.y, 50, 50},
				{},
				0,
				rl.WHITE,
			)
		case EndTile:
			rl.DrawTexturePro(
				assets.end_tex,
				rl.Rectangle{0, 0, 32, 32},
				rl.Rectangle{t.pos.x, t.pos.y, 50, 50},
				{},
				0,
				rl.WHITE,
			)
		}
		rl.DrawTexturePro(
			assets.start_tex,
			rl.Rectangle{0, 0, 64, 64},
			rl.Rectangle{level.start.x, level.start.y, 50, 50},
			{},
			0,
			rl.WHITE,
		)
	}
}

draw_player :: proc(plr: ^Player, assets: Assets) {
	texture_rec := rl.Rectangle{9, 10, 11, 21}
	if plr.grounded {
		if abs(plr.input) > 0 {
			t := i32(rl.GetTime() * 7) % 4
			switch t {
			case 0:
				texture_rec.x = 75
			case 1 | 3:
				texture_rec.x = 9
			case 2:
				texture_rec.x = 105
			}
			if (t == 1 || t == 3) && plr.walk_time != t {
				rl.PlaySound(assets.walk_sound)
			}
			plr.walk_time = t
		}
	} else {
		texture_rec.x = 40
		texture_rec.y = 7
		texture_rec.width = 15
		texture_rec.height = 25
	}
	if plr.dir < 0 {
		texture_rec.width = -texture_rec.width
	}

	plr_rect := rl.Rectangle{plr.pos.x, plr.pos.y, plr.size.x, plr.size.y}
	rl.DrawTexturePro(assets.player_tex, texture_rec, plr_rect, {}, 0, rl.WHITE)
}
