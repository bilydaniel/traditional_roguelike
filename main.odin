package main

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import la "core:math/linalg"
import "core:mem"
import "core:mem/virtual"
import "core:time"

import gl "vendor:OpenGL"
import "vendor:glfw"

//TODO:
// combat - basics to figure out if its fun, how much polish ads to the fun?
// fov
// level generation
// pathfinding
// ui
// inventory
// spells / talents / specialities

//TODO: I SHOULD PROBABLY SWITCH TO SOME OTHER MEASUREMENT OF SIZE FROM PIXELS

//TODO: @add facing based on the last attack, turning could be slow, not instant, when you do left arrow nad you face right you gonna only turn a bit, if you are backpaddling you can trip over or something to punish kiting...
//TODO: @add start doing ui, add log quickly, alot of games in roguelike is based on a log

//TODO: add ebo to have less data to draw
//TODO: instanced rendering, use glDrawArraysInstanced
//TODO: use debug callback gl.Enable(gl.DEBUG_OUTPUT) + gl.DebugMessageCallback(...)


Game_state :: struct {
	//TODO: cache lines
	levels:        [dynamic]Level,
	current_level: u32,
	entities:      Entities,
	entity_map:    map[u32]u32,
	dt:            f64,
}

game_state_init :: proc() -> ^Game_state {
	//TODO: use a permanent arena, can i somehow investigate the memory usage?
	game_state := new(Game_state)
	init_entities(&game_state.entities)
	append(&game_state.levels, Level{})
	level := &game_state.levels[0]
	for i := 0; i < len(level.tiles); i += 1 {
		if i > 0 && i < 100 {
			level.tiles[i] = Tile {
				asset_id = .wall,
				color    = {176.0 / 255, 79.0 / 255, 56.0 / 255, 1.0},
				solid    = true,
			}
		} else {
			level.tiles[i] = Tile {
				asset_id = .floor,
				color    = {93.0 / 255, 93.0 / 255, 93.0 / 255, 1.0},
				solid    = false,
			}
		}
	}


	sprite_table = build_sprite_table()

	spawn_entities(&game_state.entities)

	return game_state
}

frame_arena: virtual.Arena
frame_allocator: mem.Allocator

main :: proc() {
	//TODO: need a different kind of profiling for a game
	begin_profile()
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	//TODO: reserve more at start?
	arena_err := virtual.arena_init_growing(&frame_arena)
	if arena_err != nil {
		log.error("failed to init arena")
		return
	}
	frame_allocator = virtual.arena_allocator(&frame_arena)

	game_state := game_state_init()

	renderer, ok := init_renderer()
	if !ok {
		return
	}

	fps: u32 = 0
	fps_time: f64 = 0
	last_time := glfw.GetTime()
	for !glfw.WindowShouldClose(renderer.window) {
		frame_start := glfw.GetTime()
		game_state.dt = frame_start - last_time
		fps_time += game_state.dt
		fps += 1
		last_time = frame_start

		glfw.PollEvents()


		window := renderer.window

		input(window, game_state, &renderer)

		ai(game_state)

		physics_block := time_block(.physics)
		physics(game_state)
		block_end(physics_block)


		// DRAW
		draw_game_state(&renderer, game_state)

		if fps_time >= 1 {
			fmt.printf("\rfps: %d", fps)
			fps_time -= 1
			fps = 0
		}

		frame_elapsed := glfw.GetTime() - frame_start
		remaining := FRAME_TIME - frame_elapsed
		sleep_block := time_block(.sleep)
		if remaining > 0 {
			time.sleep(time.Duration(remaining * 1e9)) // seconds -> nanoseconds
		}
		block_end(sleep_block)
	}
	end_profile()
}
