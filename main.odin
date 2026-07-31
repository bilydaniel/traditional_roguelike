package main

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import la "core:math/linalg"
import "core:mem"
import "core:mem/virtual"
import "core:os"
import "core:sort"
import "core:strings"
import "core:time"
import stbi "vendor:stb/image"

import gl "vendor:OpenGL"
import "vendor:glfw"

//TODO:
// profile the entity dereference, is hashing slow?
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
	camera:        Camera,
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


	camera := Camera{}
	camera.zoom = 1.0
	camera.smoothing = 5.0
	game_state.camera = camera

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
	slashing := false
	for !glfw.WindowShouldClose(renderer.window) {
		frame_start := glfw.GetTime()
		game_state.dt = frame_start - last_time
		fps_time += game_state.dt
		fps += 1
		last_time = frame_start

		glfw.PollEvents()


		window := renderer.window

		input(window, game_state)

		ai(game_state)

		physics_block := time_block(.physics)
		physics(game_state)
		block_end(physics_block)


		// DRAW
		entities := &game_state.entities
		player_id := entities.player_id
		player := get_entity(entities, player_id)
		circle := get_entity_collider(player)

		levels := game_state.levels
		current_level_index := game_state.current_level
		current_level := &levels[current_level_index]

		draw_block := time_block(.draw)
		w, h := glfw.GetFramebufferSize(window)
		gl.Viewport(0, 0, w, h)
		//gl.ClearColor(0.4, 0.04, 0.41, 1.0) // TODO: figure out a better color
		gl.ClearColor(42 / 255, 42 / 255, 42 / 255, 1.0) // TODO: figure out a better color
		gl.Clear(gl.COLOR_BUFFER_BIT) // uses the color to clear

		player_center := player.pos + player.size * 0.5
		camera := &game_state.camera
		target := player_center - la.Vector2f32{f32(w), f32(h)} * 0.5 / camera.zoom
		t := 1.0 - math.exp(-camera.smoothing * f32(game_state.dt))
		camera.pos += (target - camera.pos) * t

		gl.Uniform2f(renderer.u_res, f32(w), f32(h))
		gl.Uniform1i(renderer.u_tex, 0)
		gl.Uniform2f(renderer.u_cam, camera.pos.x, camera.pos.y)
		gl.Uniform1f(renderer.u_zoom, camera.zoom)

		gl.BindVertexArray(renderer.vao)


		for tile, index in current_level.tiles {
			push_quad_tile(&renderer.vertices, index, sprite_table[tile.asset_id], tile.color)
		}

		//TODO: figure out something smarter, iterator?
		for entity, index in game_state.entities.entities {
			if entity.kind != .nil { 	// sentinel
				push_quad_entity(&renderer.vertices, entity)
			}
		}


		player_collider := get_entity_collider(player)
		//TODO: how to rotate the asset?
		push_quad(
			&renderer.vertices,
			{player_collider.x, player_collider.y, TILE_W * TILE_SCALE, TILE_H * TILE_SCALE},
			sprite_table[.arrow_full],
			{1.0, 1.0, 1.0, 1.0},
		)

		if !slashing {
			push_slash_arc(
				&renderer.vertices,
				{player_collider.x, player_collider.y},
				18,
				40,
				player.rotation,
				math.PI * 0.6, // ~108° wide
				[4]f32{1, 1, 1, 1 - t}, // white, fades out
			)
			slashing = true
		}


		//TODO: figure out the correct position and size of the collision circle, seems off
		// when do i apply scaling??
		//TODO: doesent work with walls, works fine with entities

		for i: u32 = 0; i < entities.entity_count; i += 1 {
			circle := get_entity_collider(&entities.entities[i])
			push_circle(&renderer.vertices, {circle.x, circle.y}, circle.r, {1.0, 1.0, 1.0, 1.0})
		}


		//push_quad_entity(&vertices, player)
		flush_batch(&renderer.vertices, renderer.vbo)
		glfw.SwapBuffers(window)
		block_end(draw_block)

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


window_resize :: proc "cdecl" (window: glfw.WindowHandle, width: i32, height: i32) {
	gl.Viewport(0, 0, width, height)
}


push_quad_entity :: proc(vertices: ^[dynamic]f32, entity: Entity) {
	destination := Rect {
		x = entity.pos.x,
		y = entity.pos.y,
		w = entity.size.x,
		h = entity.size.y,
	}


	id := entity.asset_id
	source := sprite_table[id]

	color := entity.color
	push_quad(vertices, destination, source, color)
}


push_quad_tile :: proc(vertices: ^[dynamic]f32, index: int, sprite: Sprite, color: Color) {
	tile_pos := get_tile_pos(u32(index))
	pixel_pos := get_tile_pixel_pos(tile_pos)
	destination := Rect {
		x = f32(pixel_pos.x),
		y = f32(pixel_pos.y),
		w = TILE_W * TILE_SCALE,
		h = TILE_H * TILE_SCALE,
	}
	push_quad(vertices, destination, sprite, color)
}

push_quad :: proc(vertices: ^[dynamic]f32, destination: Rect, source: Sprite, color: [4]f32) {
	//TODO: probably come up with more efficient way of doing this, feels messy
	x, y, w, h := destination.x, destination.y, destination.w, destination.h
	u0, v0, u1, v1 := source.u0, source.v0, source.u1, source.v1
	//TODO: could be fun to make a gradient with two colors
	r, g, b, a := color[0], color[1], color[2], color[3]
	
	//odinfmt: disable
	append(vertices,
		x,     y,     u0, v0, r, g, b, a,
		x + w, y,     u1, v0, r, g, b, a,
		x + w, y + h, u1, v1, r, g, b, a,

		x,     y,     u0, v0, r, g, b, a,
		x + w, y + h, u1, v1, r, g, b, a,
		x,     y + h, u0, v1, r, g, b, a,
	)
	//odinfmt: enable
}

flush_batch :: proc(vertices: ^[dynamic]f32, vbo: u32) {
	if len(vertices) > 0 {
		gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
		gl.BufferData(
			gl.ARRAY_BUFFER,
			len(vertices) * size_of(f32),
			raw_data(vertices^),
			gl.DYNAMIC_DRAW,
		)
		gl.DrawArrays(gl.TRIANGLES, 0, i32(len(vertices) / 8)) //TODO: change 4 to a variable
		clear(vertices)
	}
}
push_slash_arc :: proc(
	vertices: ^[dynamic]f32,
	center: la.Vector2f32,
	inner_r, outer_r: f32,
	facing_angle: f32,
	arc_width: f32,
	color: [4]f32,
	segments: int = 10,
) {
	start_angle := facing_angle - arc_width / 2
	step := arc_width / f32(segments)
	r, g, b, a := color[0], color[1], color[2], color[3]

	for i := 0; i < segments; i += 1 {
		a0 := start_angle + step * f32(i)
		a1 := start_angle + step * f32(i + 1)

		d0 := la.Vector2f32{math.cos(a0), math.sin(a0)}
		d1 := la.Vector2f32{math.cos(a1), math.sin(a1)}

		in0, out0 := center + d0 * inner_r, center + d0 * outer_r
		in1, out1 := center + d1 * inner_r, center + d1 * outer_r
		
	        //odinfmt: disable
        append(vertices,
            in0.x,  in0.y,  -1, -1, r, g, b, a,
            out0.x, out0.y, -1, -1, r, g, b, a,
            out1.x, out1.y, -1, -1, r, g, b, a,

            in0.x,  in0.y,  -1, -1, r, g, b, a,
            out1.x, out1.y, -1, -1, r, g, b, a,
            in1.x,  in1.y,  -1, -1, r, g, b, a,
        )
        //odinfmt: enable
	}
}

push_circle :: proc(
	vertices: ^[dynamic]f32,
	center: la.Vector2f32,
	radius: f32,
	color: [4]f32,
	segments: int = 32,
) {
	step := (math.PI * 2) / f32(segments)
	r, g, b, a := color[0], color[1], color[2], color[3]

	for i := 0; i < segments; i += 1 {
		a0 := step * f32(i)
		a1 := step * f32(i + 1)

		p0 := center + la.Vector2f32{math.cos(a0), math.sin(a0)} * radius
		p1 := center + la.Vector2f32{math.cos(a1), math.sin(a1)} * radius
		
	        //odinfmt: disable
        append(vertices,
            center.x, center.y, -1, -1, r, g, b, a,
            p0.x,     p0.y,     -1, -1, r, g, b, a,
            p1.x,     p1.y,     -1, -1, r, g, b, a,
        )
        //odinfmt: enable
	}
}

push_ring :: proc(
	vertices: ^[dynamic]f32,
	center: la.Vector2f32,
	inner_r, outer_r: f32,
	color: [4]f32,
	segments: int = 32,
) {
	step := (math.PI * 2) / f32(segments)
	r, g, b, a := color[0], color[1], color[2], color[3]

	for i := 0; i < segments; i += 1 {
		a0 := step * f32(i)
		a1 := step * f32(i + 1)

		d0 := la.Vector2f32{math.cos(a0), math.sin(a0)}
		d1 := la.Vector2f32{math.cos(a1), math.sin(a1)}

		in0, out0 := center + d0 * inner_r, center + d0 * outer_r
		in1, out1 := center + d1 * inner_r, center + d1 * outer_r
		
	        //odinfmt: disable
        append(vertices,
            in0.x,  in0.y,  -1, -1, r, g, b, a,
            out0.x, out0.y, -1, -1, r, g, b, a,
            out1.x, out1.y, -1, -1, r, g, b, a,

            in0.x,  in0.y,  -1, -1, r, g, b, a,
            out1.x, out1.y, -1, -1, r, g, b, a,
            in1.x,  in1.y,  -1, -1, r, g, b, a,
        )
        //odinfmt: enable
	}
}
//TODO: @finish
// try_attack_hit :: proc(player: Entity, enemies: []Entity, outer_r: f32, arc_width: f32) {
// 	for &enemy in enemies {
// 		to_enemy := enemy.pos - player.pos
// 		dist := la.length(to_enemy)
// 		if dist > outer_r + enemy.collider.r do continue // out of range
//
// 		angle_to_enemy := math.atan2(to_enemy.y, to_enemy.x)
// 		diff := angle_diff(player.facing_angle, angle_to_enemy)
// 		if abs(diff) <= arc_width / 2 {
// 			apply_damage(&enemy, player.attack_damage)
// 		}
// 	}
// }
//
// // shortest signed distance between two angles, handles wraparound at +-PI
// angle_diff :: proc(a, b: f32) -> f32 {
// 	d := b - a
// 	for d > math.PI {d -= math.PI * 2}
// 	for d < -math.PI {d += math.PI * 2}
// 	return d
// }
