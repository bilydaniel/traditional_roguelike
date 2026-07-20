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

TARGET_FPS :: 144
FRAME_TIME :: 1.0 / TARGET_FPS
TILE_W :: 16
TILE_H :: 24
TILE_SCALE :: 3

LEVEL_W :: 100
LEVEL_H :: 100


tileset_w: i32
tileset_h: i32

//TODO: camera
//TODO: add ebo to have less data to draw
//TODO: instanced rendering, use glDrawArraysInstanced
//TODO: use debug callback gl.Enable(gl.DEBUG_OUTPUT) + gl.DebugMessageCallback(...)
Rect :: struct {
	x: f32,
	y: f32,
	w: f32,
	h: f32,
}


Game_state :: struct {
	levels:        [dynamic]Level,
	current_level: u32,
	entities:      [4096]Entity,
}

Entity :: struct {
	//TODO: did anton put generation into entity?
	pos:      la.Vector2f32,
	size:     la.Vector2f32,
	speed:    f32,
	asset_id: u32,
	color:    [4]f32,
}

Tile :: struct {
	asset_id: u32,
	color:    [4]f32,
}

Level :: struct {
	tiles: [LEVEL_W * LEVEL_H]Tile,
}

Camera :: struct {
	pos:       la.Vector2f32,
	zoom:      f32,
	smoothing: f32,
}

game_state_init :: proc() -> ^Game_state {
	//TODO: permanent arena??
	game_state := new(Game_state)
	append(&game_state.levels, Level{})
	level := &game_state.levels[0]
	for i := 0; i < len(level.tiles); i += 1 {
		level.tiles[i] = Tile {
			asset_id = 24832,
			color    = {0.08, 0.07, 0.04, 1},
		}
	}

	for i := 0; i < 10; i += 1 {
		game_state.entities[i] = Entity {
			pos      = la.Vector2f32{f32(i * 50), f32(i * 50)},
			speed    = 200,
			size     = la.Vector2f32{TILE_W * TILE_SCALE, TILE_H * TILE_SCALE},
			asset_id = 24077,
			color    = [4]f32{0.8, 0.0, 0.0, 1.0},
		}
	}
	return game_state
}

main :: proc() {
	game_state := game_state_init()
	camera := Camera{}
	camera.zoom = 1.0
	camera.smoothing = 5.0
	player := Entity {
		pos      = la.Vector2f32{100, 100},
		size     = la.Vector2f32{TILE_W * TILE_SCALE, TILE_H * TILE_SCALE},
		speed    = 200,
		asset_id = 1,
		color    = [4]f32{0.8, 0.3, 0.8, 1.0},
	}


	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

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
	fmt.println(width, height)
	tileset_w = width
	tileset_h = height

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


	playerDest := Rect {
		x = 100,
		y = 100,
		w = 32,
		h = 48,
	}

	playerSource := Rect {
		x = f32(2 * TILE_W) / f32(width), // column 5 — pick your player's tile
		y = f32(1 * TILE_H) / f32(height), // row 2
		w = f32(TILE_W) / f32(width),
		h = f32(TILE_H) / f32(height),
	}
	playerColor: [4]f32 = {1.0, 0.0, 1.0, 1.0}


	fps: u32 = 0
	fps_time: f64 = 0
	last_time := glfw.GetTime()
	for !glfw.WindowShouldClose(window) {
		frame_start := glfw.GetTime()
		dt := frame_start - last_time
		fps_time += dt
		fps += 1
		last_time = frame_start

		glfw.PollEvents() //TODO: when should i poll??

		if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS {
			glfw.SetWindowShouldClose(window, true)
		}

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
		if movement.x != 0 && movement.y != 0 {
			movement = la.normalize(movement)
		}
		player.pos += movement * player.speed * f32(dt)


		w, h := glfw.GetFramebufferSize(window)
		gl.Viewport(0, 0, w, h)
		gl.ClearColor(0.24, 0.04, 0.41, 1.0) // TODO: figure out a better color
		gl.Clear(gl.COLOR_BUFFER_BIT) // uses the color to clear

		player_center := player.pos + player.size * 0.5
		target := player_center - la.Vector2f32{f32(w), f32(h)} * 0.5 / camera.zoom
		t := 1.0 - math.exp(-camera.smoothing * f32(dt))
		camera.pos += (target - camera.pos) * t

		gl.Uniform2f(u_res, f32(w), f32(h))
		gl.Uniform1i(u_tex, 0)
		gl.Uniform2f(u_cam, camera.pos.x, camera.pos.y)
		gl.Uniform1f(u_zoom, camera.zoom)

		gl.BindVertexArray(vao)

		levels := game_state.levels
		current_level_index := game_state.current_level
		current_level := &levels[current_level_index]

		for tile, index in current_level.tiles {
			push_quad_tile(&vertices, tile, index)
		}

		for entity in game_state.entities {
			push_quad_entity(&vertices, entity)
		}

		push_quad_entity(&vertices, player)
		flush_batch(&vertices, vbo)
		glfw.SwapBuffers(window)

		if fps_time >= 1 {
			fmt.printf("\rfps: %d", fps)
			fps_time -= 1
			fps = 0
		}

		frame_elapsed := glfw.GetTime() - frame_start
		remaining := FRAME_TIME - frame_elapsed
		if remaining > 0 {
			time.sleep(time.Duration(remaining * 1e9)) // seconds -> nanoseconds
		}
	}
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


	id := f32(entity.asset_id)
	x := i32(math.mod(id, f32(tileset_w / TILE_W)))
	y := i32(id / f32(tileset_w / TILE_W))

	source := Rect {
		x = f32(x * TILE_W) / f32(tileset_w),
		y = f32(y * TILE_H) / f32(tileset_h),
		w = f32(TILE_W) / f32(tileset_w),
		h = f32(TILE_H) / f32(tileset_h),
	}

	color := entity.color
	push_quad(vertices, destination, source, color)
}


push_quad_tile :: proc(vertices: ^[dynamic]f32, tile: Tile, index: int) {
	idx := f32(index)
	x_dest := math.mod(idx, f32(LEVEL_W))
	y_dest := idx / f32(LEVEL_W)

	destination := Rect {
		x = x_dest * TILE_W * TILE_SCALE,
		y = y_dest * TILE_H * TILE_SCALE,
		w = TILE_W * TILE_SCALE,
		h = TILE_H * TILE_SCALE,
	}


	id := f32(tile.asset_id)
	x := i32(math.mod(id, f32(tileset_w / TILE_W)))
	y := i32(id / f32(tileset_w / TILE_W))

	source := Rect {
		x = f32(x * TILE_W) / f32(tileset_w),
		y = f32(y * TILE_H) / f32(tileset_h),
		w = f32(TILE_W) / f32(tileset_w),
		h = f32(TILE_H) / f32(tileset_h),
	}

	color := tile.color
	push_quad(vertices, destination, source, color)
}

push_quad :: proc(vertices: ^[dynamic]f32, destination: Rect, source: Rect, color: [4]f32) {
	//TODO: probably come up with more efficient way of doing this, feels messy
	x, y, w, h := destination.x, destination.y, destination.w, destination.h
	u0, v0, u1, v1 := source.x, source.y, source.x + source.w, source.y + source.h
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
