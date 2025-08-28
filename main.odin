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
	pos:           [2]f32,
	vel:           [2]f32,
	size:          [2]f32,
	speed:         f32,
	jump_force:    f32,
	grounded:      bool,
	checkpoint:    [2]f32,
	jumps:         i32,
	input:         f32,
	dir:           f32,
	walk_time:     i32,
	found_biscuit: bool,
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
	pos:    [2]f32,
	active: bool,
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
	// Textures
	floor_tex:            rl.Texture2D,
	floor_top_tex:        rl.Texture2D,
	floor_lef_tex:        rl.Texture2D,
	floor_rig_tex:        rl.Texture2D,
	floor_cen_tex:        rl.Texture2D,
	spike_tex:            rl.Texture2D,
	checkpoint_down_tex:  rl.Texture2D,
	checkpoint_up_tex:    rl.Texture2D,
	start_tex:            rl.Texture2D,
	end_tex:              rl.Texture2D,
	player_tex:           rl.Texture2D,
	biscuits_found_tex:   rl.Texture2D,

	// Sounds
	jump_sound:           rl.Sound,
	jump_fail_sound:      rl.Sound,
	checkpoint_sound:     rl.Sound,
	finish_sound:         rl.Sound,
	walk_sound:           rl.Sound,
	death_sound:          rl.Sound,
	biscuits_found_sound: rl.Sound,

	// Cutscene lines
	line1_sound:          rl.Sound,
	line2_sound:          rl.Sound,
	line3_sound:          rl.Sound,

	// Cutscene frames
	frame1_tex:           rl.Texture2D,
	frame2_tex:           rl.Texture2D,
	frame3_tex:           rl.Texture2D,
	frame4_tex:           rl.Texture2D,
	frame5_tex:           rl.Texture2D,
	frame6_tex:           rl.Texture2D,
	frame7_tex:           rl.Texture2D,
	frame8_tex:           rl.Texture2D,
	frame9_tex:           rl.Texture2D,
	frame10_tex:          rl.Texture2D,
}

main :: proc() {
	rl.InitWindow(1600, 900, "B I S C U I T")
	rl.InitAudioDevice()
	rl.SetTargetFPS(60)
	rl.SetExitKey(rl.KeyboardKey.F4)

	assets := load_assets("assets")
	levels := load_levels("assets/levels")

	play_cutscene(assets)

	current_level := 0
	level := levels[current_level]

	plr: Player
	plr.size = {17, 33}
	plr.pos = level.start + plr.size / 2
	plr.checkpoint = plr.pos
	plr.speed = 6
	plr.jump_force = 12
	plr.jumps = 2
	plr.dir = 1

	play_walk: bool
	walk_time: i32

	level_transition: f32
	game_finished: bool
	game_just_finished: bool

	show_collision: bool

	cam := rl.Camera2D{{}, {}, 0, 1}
	dt: f32 = 0
	for !rl.WindowShouldClose() {
		dt = rl.GetFrameTime()
		if rl.IsKeyPressed(rl.KeyboardKey.F11) {
			rl.ToggleFullscreen()
		}

		if !game_finished {
			cam.target = linalg.lerp(
				cam.target,
				linalg.floor(plr.pos / {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}) *
				{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())},
				dt * 4,
			)

			if !plr.found_biscuit {
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

				if rl.IsKeyPressed(rl.KeyboardKey.R) {
					plr.pos = level.start + plr.size * 0.5
					plr.checkpoint = plr.pos
				}
			}

			player_collision(&level, &plr, assets, dt)
			plr.pos += plr.vel * dt
		}

		if rl.IsKeyPressed(rl.KeyboardKey.F2) {
			show_collision = !show_collision
		}

		rl.BeginDrawing()

		rl.ClearBackground(rl.Color{120, 120, 110, 255})

		if !game_finished {
			rl.BeginMode2D(cam)

			draw_level(level, assets)
			draw_player(&plr, assets)
			if show_collision {
				draw_collision(level, plr)
			}

			if current_level == 0 {
				rl.DrawText(
					"Press 'W' to jump\nUse 'A' and 'D' to move\nJump in the air to double jump\nPress 'R' to restart",
					98,
					252,
					30,
					rl.BLACK,
				)
				rl.DrawText(
					"Press 'W' to jump\nUse 'A' and 'D' to move\nJump in the air to double jump\nPress 'R' to restart",
					100,
					250,
					30,
					rl.DARKBLUE,
				)
			}

			rl.EndMode2D()

			rl.DrawText("Press 'R' to restart", 3, 900 - 18, 20, rl.BLACK)
			rl.DrawText("Press 'R' to restart", 5, 900 - 20, 20, rl.DARKBLUE)
		}

		rl.DrawFPS(0, 0)

		if game_finished {
			if game_just_finished && level_transition <= 0 {
				game_just_finished = false
				rl.PlaySound(assets.biscuits_found_sound)
			}
			rl.DrawTexturePro(
				assets.biscuits_found_tex,
				rl.Rectangle{0, 0, 480, 270},
				rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())},
				{},
				0,
				rl.WHITE,
			)
			rl.DrawText(
				"Thanks for playing!\nThis was my submission for the\nBrackeys Game Jam 2025.2",
				8,
				802,
				30,
				rl.BLACK,
			)
			rl.DrawText(
				"Thanks for playing!\nThis was my submission for the\nBrackeys Game Jam 2025.2",
				10,
				800,
				30,
				rl.DARKBLUE,
			)

			btn_rec := rl.Rectangle{1375, 775, 200, 100}
			rl.DrawRectangleRec(btn_rec, rl.RED)
			rl.DrawText("Quit", 1380, 780, 100, rl.BLACK)
			if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
				if rl.CheckCollisionPointRec(rl.GetMousePosition(), btn_rec) {
					break
				}
			}
		}


		if plr.found_biscuit {
			level_transition += dt
			rl.DrawRectangle(
				0,
				0,
				rl.GetScreenWidth(),
				rl.GetScreenHeight(),
				rl.Fade(rl.BLACK, level_transition),
			)
			if level_transition >= 1 {
				current_level += 1
				if current_level < len(levels) {
					level = levels[current_level]
					plr.found_biscuit = false
					plr.pos = level.start + plr.size / 2
					plr.checkpoint = plr.pos
				} else {
					game_finished = true
					game_just_finished = true
					plr.found_biscuit = false
				}
			}
		} else if level_transition > 0 {
			level_transition -= dt
			rl.DrawRectangle(
				0,
				0,
				rl.GetScreenWidth(),
				rl.GetScreenHeight(),
				rl.Fade(rl.BLACK, level_transition),
			)
		}

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
			slice.reverse(file_infos)
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
							level.tiles[i] = CheckpointTile{pos, false}
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
	assets.checkpoint_down_tex = rl.LoadTexture("assets/textures/flag_down.png")
	assets.checkpoint_up_tex = rl.LoadTexture("assets/textures/flag_up.png")
	assets.start_tex = rl.LoadTexture("assets/kenny/PNG/Other/doorRed_top.png")
	assets.end_tex = rl.LoadTexture("assets/textures/biscuit.png")
	assets.player_tex = rl.LoadTexture("assets/textures/player.png")
	assets.biscuits_found_tex = rl.LoadTexture("assets/textures/biscuits_found.png")

	assets.jump_sound = rl.LoadSound("assets/sounds/jump.wav")
	assets.jump_fail_sound = rl.LoadSound("assets/sounds/jump_fail.wav")
	assets.checkpoint_sound = rl.LoadSound("assets/sounds/checkpoint.wav")
	assets.finish_sound = rl.LoadSound("assets/sounds/finish.wav")
	assets.walk_sound = rl.LoadSound("assets/sounds/walk.wav")
	assets.death_sound = rl.LoadSound("assets/sounds/death.wav")
	assets.biscuits_found_sound = rl.LoadSound("assets/sounds/biscuits_found.wav")

	assets.line1_sound = rl.LoadSound("assets/sounds/line1.wav")
	assets.line2_sound = rl.LoadSound("assets/sounds/line2.wav")
	assets.line3_sound = rl.LoadSound("assets/sounds/line3.wav")

	assets.frame1_tex = rl.LoadTexture("assets/textures/frame1.png")
	assets.frame2_tex = rl.LoadTexture("assets/textures/frame2.png")
	assets.frame3_tex = rl.LoadTexture("assets/textures/frame3.png")
	assets.frame4_tex = rl.LoadTexture("assets/textures/frame4.png")
	assets.frame5_tex = rl.LoadTexture("assets/textures/frame5.png")
	assets.frame6_tex = rl.LoadTexture("assets/textures/frame6.png")
	assets.frame7_tex = rl.LoadTexture("assets/textures/frame7.png")
	assets.frame8_tex = rl.LoadTexture("assets/textures/frame8.png")
	assets.frame9_tex = rl.LoadTexture("assets/textures/frame9.png")
	assets.frame10_tex = rl.LoadTexture("assets/textures/frame10.png")
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
				t.active ? assets.checkpoint_up_tex : assets.checkpoint_down_tex,
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
				rl.Rectangle{t.pos.x, t.pos.y + f32(math.sin(rl.GetTime()) * 12), 50, 50},
				{},
				0,
				rl.WHITE,
			)
		}
	}
}

draw_player :: proc(plr: ^Player, assets: Assets) {
	texture_rec := rl.Rectangle{9, 10, 11, 21}
	if plr.grounded && !plr.found_biscuit {
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

player_collision :: proc(level: ^Level, plr: ^Player, assets: Assets, dt: f32) {
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
	for &tile, i in level.tiles {
		switch &t in tile {
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
			tile_rect := rl.Rectangle {
				t.pos.x,
				t.pos.y + TILE_SIZE * 0.5,
				TILE_SIZE,
				TILE_SIZE * 0.5,
			}
			switch t.dir {
			case .Up:
			case .Down:
				tile_rect.y = t.pos.y
			case .Left:
				tile_rect.x = t.pos.x + TILE_SIZE * 0.5
				tile_rect.y = t.pos.y
				tile_rect.width = TILE_SIZE * 0.5
				tile_rect.height = TILE_SIZE
			case .Right:
				tile_rect.y = t.pos.y
				tile_rect.width = TILE_SIZE * 0.5
				tile_rect.height = TILE_SIZE
			}
			if rl.CheckCollisionRecs(tile_rect, test_rect) {
				plr.pos = plr.checkpoint
				plr.vel = {0, 0}
				rl.PlaySound(assets.death_sound)
			}
		case CheckpointTile:
			tile_rect := rl.Rectangle{t.pos.x, t.pos.y, TILE_SIZE, TILE_SIZE}
			if rl.CheckCollisionRecs(tile_rect, test_rect) {
				if !t.active {
					plr.checkpoint = t.pos
					rl.PlaySound(assets.checkpoint_sound)
					t.active = true
				}
			}
		case EndTile:
			tile_rect := rl.Rectangle{t.pos.x, t.pos.y, TILE_SIZE, TILE_SIZE}
			if rl.CheckCollisionRecs(tile_rect, plr_rect) && !plr.found_biscuit {
				plr.found_biscuit = true
				plr.vel = {}
				rl.PlaySound(assets.finish_sound)
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
			if col.normal.x > 0 {
				plr.vel.x = 0
				plr.pos.x = col.point.x
			}
			if col.normal.x < 0 {
				plr.vel.x = 0
				plr.pos.x = col.point.x - plr.size.x * 0.51
			}
			if col.normal.y > 0 {
				plr.vel.y = 0
				plr.pos.y = col.point.y
			}
			if col.normal.y < 0 {
				plr.vel.y = 0
				plr.pos.y = col.point.y - plr.size.y * 0.51
			}
		case physics.CollisionMiss:
		}
	}
}

draw_collision :: proc(level: Level, plr: Player) {
	plr_rect := rl.Rectangle{plr.pos.x, plr.pos.y, plr.size.x, plr.size.y}
	rl.DrawRectangleRec(plr_rect, rl.Fade(rl.GREEN, .5))
	for tile in level.tiles {
		tile_rect: rl.Rectangle
		switch &t in tile {
		case BasicTile:
			tile_rect = rl.Rectangle{t.pos.x, t.pos.y, TILE_SIZE, TILE_SIZE}
		case DeathTile:
			tile_rect = rl.Rectangle {
				t.pos.x,
				t.pos.y + TILE_SIZE * 0.5,
				TILE_SIZE,
				TILE_SIZE * 0.5,
			}
			switch t.dir {
			case .Up:
			case .Down:
				tile_rect.y = t.pos.y
			case .Left:
				tile_rect.x = t.pos.x + TILE_SIZE * 0.5
				tile_rect.y = t.pos.y
				tile_rect.width = TILE_SIZE * 0.5
				tile_rect.height = TILE_SIZE
			case .Right:
				tile_rect.y = t.pos.y
				tile_rect.width = TILE_SIZE * 0.5
				tile_rect.height = TILE_SIZE
			}
		case CheckpointTile:
			tile_rect = rl.Rectangle{t.pos.x, t.pos.y, TILE_SIZE, TILE_SIZE}
		case EndTile:
			tile_rect = rl.Rectangle{t.pos.x, t.pos.y, TILE_SIZE, TILE_SIZE}
		}
		rl.DrawRectangleRec(tile_rect, rl.Fade(rl.GREEN, .5))
	}
}

play_cutscene :: proc(assets: Assets) {
	line1: bool
	line2: bool
	line3: bool
	time: f32

	frame_rec := rl.Rectangle{0, 0, 480, 270}
	dest_rec := rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground(rl.SKYBLUE)

		tex := assets.frame1_tex
		if time >= 1 {
			tex = assets.frame2_tex
		}
		if time >= 3.8 {
			tex = assets.frame3_tex
		}
		if time >= 4 {
			tex = assets.frame4_tex
		}
		if time >= 4.2 {
			tex = assets.frame5_tex
		}
		if time >= 4.4 {
			tex = assets.frame6_tex
		}
		if time >= 4.6 {
			tex = assets.frame7_tex
		}
		if time >= 4.8 {
			tex = assets.frame8_tex
		}
		if time >= 6.9 {
			tex = assets.frame10_tex
		}
		rl.DrawTexturePro(tex, frame_rec, dest_rec, {}, 0, rl.WHITE)

		if time >= 1 && !line1 {
			rl.PlaySound(assets.line1_sound)
			line1 = true
		}
		if time >= 4.6 && !line2 {
			rl.PlaySound(assets.line2_sound)
			line2 = true
		}
		if time >= 6.9 && !line3 {
			rl.PlaySound(assets.line3_sound)
			line3 = true
		}

		if time >= 9 {
			break
		}

		rl.DrawText("Press 'Escape' to skip", 3, 900 - 18, 20, rl.BLACK)
		rl.DrawText("Press 'Escape' to skip", 5, 900 - 20, 20, rl.DARKBLUE)
		if rl.IsKeyPressed(rl.KeyboardKey.ESCAPE) {
			rl.StopSound(assets.line1_sound)
			rl.StopSound(assets.line2_sound)
			rl.StopSound(assets.line3_sound)
			break
		}

		rl.EndDrawing()
		time += rl.GetFrameTime()
	}
}
