package main

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import la "core:math/linalg"
import "core:os"
import "core:strings"
import "core:time"
import stbi "vendor:stb/image"

import gl "vendor:OpenGL"
import "vendor:glfw"

//TODO:
// collision, solid tiles
// add profiler, profile some basic blocks
// profile the entity dereference, is hashing slow?
// combat - basics to figure out if its fun, how much polish ads to the fun?
// fov
// level generation
// pathfinding
// ui
// inventory
// spells / talents / specialities

//TODO: @add facing based on the last attack, turning could be slow, not instant, when you do left arrow nad you face right you gonna only turn a bit, if you are backpaddling you can trip over or something to punish kiting...
//TODO: @add start doing ui, add log quickly, alot of games in roguelike is based on a log

//TODO: add ebo to have less data to draw
//TODO: instanced rendering, use glDrawArraysInstanced
//TODO: use debug callback gl.Enable(gl.DEBUG_OUTPUT) + gl.DebugMessageCallback(...)

TARGET_FPS :: 144
FRAME_TIME :: 1.0 / TARGET_FPS

LEVEL_W :: 100
LEVEL_H :: 100


Game_state :: struct {
	//TODO: cache lines
	levels:        [dynamic]Level,
	current_level: u32,
	entities:      Entities,
	entity_map:    map[u32]u32,
	camera:        Camera,
}


Camera :: struct {
	pos:       la.Vector2f32,
	zoom:      f32,
	smoothing: f32,
}

apply_camera :: proc(camera: Camera, x_in: f32, y_in: f32) -> (x_out: f32, y_out: f32) {
	x_out = (x_in + camera.pos.x) / camera.zoom
	y_out = (y_in + camera.pos.y) / camera.zoom
	return
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


main :: proc() {
	//TODO: need a different kind of profiling for a game

	begin_profile()

	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	game_state := game_state_init()

	if !glfw.Init() {
		log.error("glfw init failed")
		return
	}
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

	window := glfw.CreateWindow(800, 600, "Traditional Roguelike", nil, nil)
	if window == nil {
		log.error("failed to create window")
		return
	}

	glfw.MakeContextCurrent(window)
	glfw.SwapInterval(0) // vsync off

	gl.load_up_to(3, 3, glfw.gl_set_proc_address)

	gl.Viewport(0, 0, 800, 600)
	//glfw.SetFramebufferSizeCallback(window, window_resize)

	vao: u32 = 0
	gl.GenVertexArrays(1, &vao)
	gl.BindVertexArray(vao)


	vbo: u32 = 0
	gl.GenBuffers(1, &vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)

	vertices: [dynamic]f32

	vertex_attrib_floats := 8
	stride := i32(vertex_attrib_floats * size_of(f32))
	gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, stride, uintptr(0))
	gl.EnableVertexAttribArray(0) // aPos
	gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, stride, uintptr(2 * size_of(f32))) // aTexCoord
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(2, 4, gl.FLOAT, gl.FALSE, stride, uintptr(4 * size_of(f32))) // aColor
	gl.EnableVertexAttribArray(2)


	shader_program, ok := shader_make("shader.vert", "shader.frag")
	if !ok {
		return
	}
	shader_use(shader_program)

	width, height, channels: i32
	atlas := stbi.load("oryx_tileset.png", &width, &height, &channels, 4) // no idea of 4 or 0
	if atlas == nil {
		log.error("failed loading file")
		return
	}

	texture: u32
	gl.GenTextures(1, &texture)
	gl.BindTexture(gl.TEXTURE_2D, texture)

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, atlas)
	//gl.GenerateMipmap(gl.TEXTURE_2D)
	stbi.image_free(atlas)

	gl.Enable(gl.BLEND) //TODO: no idea what it does
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)


	u_res := gl.GetUniformLocation(shader_program.id, "uResolution")
	u_tex := gl.GetUniformLocation(shader_program.id, "uTexture")

	u_cam := gl.GetUniformLocation(shader_program.id, "uCam")
	u_zoom := gl.GetUniformLocation(shader_program.id, "uZoom")


	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, texture)


	fps: u32 = 0
	fps_time: f64 = 0
	last_time := glfw.GetTime()
	slashing := false
	for !glfw.WindowShouldClose(window) {
		frame_start := glfw.GetTime()
		dt := frame_start - last_time
		fps_time += dt
		fps += 1
		last_time = frame_start

		glfw.PollEvents()


		levels := game_state.levels
		current_level_index := game_state.current_level
		current_level := &levels[current_level_index]

		if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS {
			glfw.SetWindowShouldClose(window, true)
		}

		entities := &game_state.entities
		player_id := entities.player_id
		player := get_entity(entities, player_id)
		movement := la.Vector2f32{}
		if glfw.GetKey(window, glfw.KEY_W) == glfw.PRESS {
			movement.y -= 1
		}
		if glfw.GetKey(window, glfw.KEY_S) == glfw.PRESS {
			movement.y += 1
		}
		if glfw.GetKey(window, glfw.KEY_A) == glfw.PRESS {
			movement.x -= 1
		}
		if glfw.GetKey(window, glfw.KEY_D) == glfw.PRESS {
			movement.x += 1
		}
		if glfw.GetKey(window, glfw.KEY_UP) == glfw.PRESS {
			slashing = false
		}

		if glfw.GetKey(window, glfw.KEY_KP_ADD) == glfw.PRESS {
			game_state.camera.zoom += 0.1
		}

		if glfw.GetKey(window, glfw.KEY_KP_SUBTRACT) == glfw.PRESS {
			game_state.camera.zoom -= 0.1
		}

		mouse_x, mouse_y := glfw.GetCursorPos(window)
		world_x, world_y := apply_camera(game_state.camera, f32(mouse_x), f32(mouse_y))

		fmt.printf("player - x: %v, y: %v \n", player.pos.x, player.pos.y)
		fmt.printf("mouse -  x: %v, y: %v \n", world_x, world_y)
		fmt.printf("******************************\n")

		if movement.x != 0 && movement.y != 0 {
			movement = la.normalize(movement)
		}

		player.vel = movement * player.speed * f32(dt)
		player.pos += player.vel

		//TODO: optimize, dont check everything, only closest tiles
		for tile, index in current_level.tiles {
			if tile.solid {
				tile_collider := get_tile_collider(u32(index))
				player_collider := get_entity_collider(player)
				push, hit := collide_aabb_circle(tile_collider, player_collider)
				if hit {
					player.pos += push
				}

			}
		}


		for &entity, index in game_state.entities.entities {
			if entity.id != player_id {
				entity_collider := get_entity_collider(&entity)
				player_collider := get_entity_collider(player)

				push, hit := collide_circle_circle(player_collider, entity_collider)
				if hit {
					player.pos += push / 2
					entity.pos -= push / 2
				}
			}
		}

		w, h := glfw.GetFramebufferSize(window)
		gl.Viewport(0, 0, w, h)
		//gl.ClearColor(0.4, 0.04, 0.41, 1.0) // TODO: figure out a better color
		gl.ClearColor(42 / 255, 42 / 255, 42 / 255, 1.0) // TODO: figure out a better color
		gl.Clear(gl.COLOR_BUFFER_BIT) // uses the color to clear

		player_center := player.pos + player.size * 0.5
		camera := &game_state.camera
		target := player_center - la.Vector2f32{f32(w), f32(h)} * 0.5 / camera.zoom
		t := 1.0 - math.exp(-camera.smoothing * f32(dt))
		camera.pos += (target - camera.pos) * t

		gl.Uniform2f(u_res, f32(w), f32(h))
		gl.Uniform1i(u_tex, 0)
		gl.Uniform2f(u_cam, camera.pos.x, camera.pos.y)
		gl.Uniform1f(u_zoom, camera.zoom)

		gl.BindVertexArray(vao)


		for tile, index in current_level.tiles {
			push_quad_tile(&vertices, index, sprite_table[tile.asset_id], tile.color)
		}

		//TODO: figure out something smarter, iterator?
		for entity, index in game_state.entities.entities {
			if entity.kind != .nil { 	// sentinel
				push_quad_entity(&vertices, entity)
			}
		}


		if !slashing {
			push_slash_arc(
				&vertices,
				{100.0, 100.0},
				18, // inner radius
				40, // outer radius
				0.0,
				math.PI * 0.6, // ~108° wide
				[4]f32{1, 1, 1, 1 - t}, // white, fades out
			)
			slashing = true
			push_circle(&vertices, {150.0, 150.0}, 20.0, [4]f32{1, 1, 1, 1 - t})
			push_ring(&vertices, {170.0, 170.0}, 20.0, 35.0, [4]f32{1, 1, 1, 1 - t})

		}

		//push_quad_entity(&vertices, player)
		flush_batch(&vertices, vbo)
		glfw.SwapBuffers(window)

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

Shader :: struct {
	id: u32,
}

shader_make :: proc(vertex_path: string, fragment_path: string) -> (Shader, bool) {
	shader := Shader{}
	temp := runtime.default_temp_allocator_temp_begin()
	defer runtime.default_temp_allocator_temp_end(temp)

	vertex_shader_source, err := os.read_entire_file(vertex_path, context.temp_allocator)
	if err != nil {
		fmt.eprintfln("vertex shader read error: %s", err)
		return shader, false
	}

	fragment_shader_source, err2 := os.read_entire_file(fragment_path, context.temp_allocator)
	if err2 != nil {
		fmt.eprintfln("vertex shader read error: %s", err)
		return shader, false
	}

	vertex_shader_id := shader_compile(gl.VERTEX_SHADER, string(vertex_shader_source))
	fragment_shader_id := shader_compile(gl.FRAGMENT_SHADER, string(fragment_shader_source))

	shader_program_id := gl.CreateProgram()
	gl.AttachShader(shader_program_id, vertex_shader_id)
	gl.AttachShader(shader_program_id, fragment_shader_id)
	gl.LinkProgram(shader_program_id)
	checkProgramLinking(shader_program_id)

	gl.DeleteShader(vertex_shader_id)
	gl.DeleteShader(fragment_shader_id)

	shader.id = shader_program_id

	return shader, true
}

shader_compile :: proc(shader_type: u32, shader_source: string) -> u32 {
	shader_id := gl.CreateShader(shader_type)
	shader_source_c := strings.clone_to_cstring(shader_source, context.temp_allocator)
	gl.ShaderSource(shader_id, 1, &shader_source_c, nil)
	gl.CompileShader(shader_id)
	checkShaderCompilation(shader_id)

	return shader_id
}

shader_use :: proc(shader: Shader) {
	gl.UseProgram(shader.id)
}

shader_set_bool :: proc(shader: Shader, name: cstring, value: bool) {
	location := gl.GetUniformLocation(shader.id, name)
	gl.Uniform1i(location, i32(value))
}

shader_set_int :: proc(shader: Shader, name: cstring, value: i32) {
	location := gl.GetUniformLocation(shader.id, name)
	gl.Uniform1i(location, value)
}

shader_set_float :: proc(shader: Shader, name: cstring, value: f32) {
	location := gl.GetUniformLocation(shader.id, name)
	gl.Uniform1f(location, value)
}

checkShaderCompilation :: proc(shaderId: u32) {
	success: i32
	info: [512]u8

	gl.GetShaderiv(shaderId, gl.COMPILE_STATUS, &success)

	if success == 0 {
		gl.GetShaderInfoLog(shaderId, 512, nil, raw_data(info[:]))
		err := string(cstring(raw_data(info[:])))
		log.error(err)
	}
}

checkProgramLinking :: proc(shaderProgramId: u32) {
	success: i32
	info: [512]u8

	gl.GetProgramiv(shaderProgramId, gl.LINK_STATUS, &success)

	if success == 0 {
		gl.GetProgramInfoLog(shaderProgramId, 512, nil, raw_data(info[:]))
		err := string(cstring(raw_data(info[:])))
		log.error(err)
	}
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
