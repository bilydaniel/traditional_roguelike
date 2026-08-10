package main

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import la "core:math/linalg"
import "core:os"
import "core:strings"
import gl "vendor:OpenGL"
import "vendor:glfw"
import stbi "vendor:stb/image"

TARGET_FPS :: 144
FRAME_TIME :: 1.0 / TARGET_FPS
VIRTUAL_HEIGHT :: 240 //TODO: figure out the value

Renderer :: struct {
	window:         glfw.WindowHandle,
	camera:         Camera,
	vao:            u32,
	vbo:            u32,
	texture:        u32,
	u_res:          i32,
	u_tex:          i32,
	u_cam:          i32,
	u_zoom:         i32,
	u_world_height: i32,
	//TODO: probably split vertices onto its own arena, reset every frame
	vertices:       [dynamic]f32,
}

init_renderer :: proc() -> (renderer: Renderer, ok: bool) {
	if !glfw.Init() {
		log.error("glfw init failed")
		return
	}

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3)
	//TODO: opengl errors
	// glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	// glfw.WindowHint(glfw.OPENGL_DEBUG_CONTEXT, 1)
	//TODO: can use
	// if err := gl.GetError(); err != gl.NO_ERROR {
	// 	log.errorf("GL error 0x%x at <label>", err)
	// }

	window := glfw.CreateWindow(800, 600, "Traditional Roguelike", nil, nil)
	if window == nil {
		log.error("failed to create window")
		return
	}

	renderer.window = window

	glfw.MakeContextCurrent(window)
	glfw.SwapInterval(0) // vsync off

	gl.load_up_to(3, 3, glfw.gl_set_proc_address)

	gl.Enable(gl.DEBUG_OUTPUT)
	gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
	//gl.DebugMessageCallback(gl_debug_callback, nil)

	gl.Viewport(0, 0, 800, 600)
	//glfw.SetFramebufferSizeCallback(window, window_resize)

	vao: u32 = 0
	gl.GenVertexArrays(1, &vao)
	gl.BindVertexArray(vao)
	renderer.vao = vao


	vbo: u32 = 0
	gl.GenBuffers(1, &vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	renderer.vbo = vbo

	vertex_attrib_floats := 9
	stride := i32(vertex_attrib_floats * size_of(f32))
	gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, stride, uintptr(0))
	gl.EnableVertexAttribArray(0) // aPos
	gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, stride, uintptr(2 * size_of(f32))) // aTexCoord
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(2, 4, gl.FLOAT, gl.FALSE, stride, uintptr(4 * size_of(f32))) // aColor
	gl.EnableVertexAttribArray(2)
	gl.VertexAttribPointer(3, 1, gl.FLOAT, gl.FALSE, stride, uintptr(8 * size_of(f32))) // aDepth
	gl.EnableVertexAttribArray(3)

	shader_program, shader_ok := shader_make("shader.vert", "shader.frag")
	if !shader_ok {
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
	renderer.texture = texture

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, atlas)
	//gl.GenerateMipmap(gl.TEXTURE_2D)
	stbi.image_free(atlas)

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	gl.Enable(gl.DEPTH_TEST)

	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, texture)

	renderer.u_res = gl.GetUniformLocation(shader_program.id, "uResolution")
	renderer.u_tex = gl.GetUniformLocation(shader_program.id, "uTexture")

	renderer.u_cam = gl.GetUniformLocation(shader_program.id, "uCam")
	renderer.u_zoom = gl.GetUniformLocation(shader_program.id, "uZoom")

	renderer.u_world_height = gl.GetUniformLocation(shader_program.id, "uWorldHeight")

	renderer.camera.zoom = 1.0
	renderer.camera.smoothing = 5.0
	renderer.camera.manual = false

	ok = true
	return
}

arrow_rotation: f32 = 0

draw_game_state :: proc(renderer: ^Renderer, game_state: ^Game_state) {
	window := renderer.window
	entities := &game_state.entities
	particles := &game_state.particles
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
	gl.Clear(gl.DEPTH_BUFFER_BIT)

	player_center := player.pos + player.size * 0.5
	camera := &renderer.camera

	if !camera.manual {
		camera.zoom = f32(h) / f32(VIRTUAL_HEIGHT)
	}
	target := player_center - la.Vector2f32{f32(w), f32(h)} * 0.5 / camera.zoom
	t := 1.0 - math.exp(-camera.smoothing * f32(game_state.dt))
	camera.pos += (target - camera.pos) * t

	gl.Uniform2f(renderer.u_res, f32(w), f32(h))
	gl.Uniform1i(renderer.u_tex, 0)
	gl.Uniform2f(renderer.u_cam, camera.pos.x, camera.pos.y)
	gl.Uniform1f(renderer.u_zoom, camera.zoom)
	gl.Uniform1f(renderer.u_world_height, f32(LEVEL_H * TILE_H))

	gl.BindVertexArray(renderer.vao)

	//PARTICLES
	{
		for i: u32 = 0; i < particles.particle_count; i += 1 {
			particle := particles.particles[i]
			rect := Rect {
				particle.pos.x,
				particle.pos.y,
				particle.pos.x + particle.size.x,
				particle.pos.y + particle.size.y,
			}
			push_rect(&renderer.vertices, rect, 1.0, particle.color)
		}
	}

	for tile, index in current_level.tiles {
		push_quad_tile(&renderer.vertices, index, sprite_table[tile.asset_id], tile.color)
	}

	//TODO: figure out something smarter, iterator?
	for i: u32 = 0; i < entities.entity_count; i += 1 {
		entity := entities.entities[i]
		if entity.kind != .nil {
			push_quad_entity(&renderer.vertices, entity)
		}
	}


	player_collider := get_entity_collider(player)

	arrow_visual_offset :: 3 * math.PI / 4
	arrow_visual_rotation := arrow_rotation + arrow_visual_offset

	arrow_dir := la.Vector2f32{math.cos(arrow_rotation), math.sin(arrow_rotation)}
	arrow_orbit: f32 = 20
	player_collider_vec := la.Vector2f32{player_collider.x, player_collider.y}
	arrow_center := player_collider_vec + arrow_dir * arrow_orbit
	//TODO: how to rotate the asset?
	arrow_rotation += 0.01
	arrow_rotation = player.rotation
	push_quad_rotated(
		&renderer.vertices,
		{
			arrow_center.x - (TILE_W / 2),
			arrow_center.y - (TILE_H / 2),
			arrow_center.x + (TILE_W / 2),
			arrow_center.y + (TILE_H / 2),
		},
		sprite_table[.arrow_full],
		arrow_visual_rotation,
		{1.0, 1.0, 1.0, 1.0},
	)

	if player.attack_animation > 0 {
		//TODO: is attack_range taking scale into account?
		push_slash_arc(
			&renderer.vertices,
			{player_collider.x, player_collider.y},
			18, //TODO: @fix no idea if i should scale or not
			player.attack_range,
			1,
			player.rotation,
			player.attack_angle,
			[4]f32{1, 1, 1, 1 - t}, // white, fades out
		)
		cooldown(&player.attack_animation, f32(game_state.dt))
	}


	//TODO: figure out the correct position and size of the collision circle, seems off
	// when do i apply scaling??
	//TODO: doesent work with walls, works fine with entities

	draw_colliders := false
	for i: u32 = 0; i < entities.entity_count; i += 1 {
		if draw_colliders {
			circle := get_entity_collider(&entities.entities[i])
			push_circle(
				&renderer.vertices,
				{circle.x, circle.y},
				circle.r,
				1,
				{1.0, 1.0, 1.0, 1.0},
			)
		}
	}


	//push_quad_entity(&vertices, player)
	flush_batch(&renderer.vertices, renderer.vbo)
	glfw.SwapBuffers(window)
	block_end(draw_block)

}

Camera :: struct {
	pos:       la.Vector2f32,
	zoom:      f32,
	smoothing: f32,
	manual:    bool,
}

apply_camera :: proc(camera: Camera, x_in: f32, y_in: f32) -> (x_out: f32, y_out: f32) {
	x_out = (x_in / camera.zoom) + camera.pos.x
	y_out = (y_in / camera.zoom) + camera.pos.y
	return
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


window_resize :: proc "cdecl" (window: glfw.WindowHandle, width: i32, height: i32) {
	gl.Viewport(0, 0, width, height)
}

rotate_point :: proc(
	point_x: f32,
	point_y: f32,
	center: la.Vector2f32,
	cos: f32,
	sin: f32,
) -> (
	rotated_x: f32,
	rotated_y: f32,
) {
	point_x_origin := point_x - center[0]
	point_y_origin := point_y - center[1]

	rotated_x = center[0] + (point_x_origin * cos) - (point_y_origin * sin)
	rotated_y = center[1] + (point_x_origin * sin) + (point_y_origin * cos)
	return
}

push_quad_rotated :: proc(
	vertices: ^[dynamic]f32,
	destination: Rect,
	source: Sprite,
	rotation: f32,
	color: [4]f32,
) {
	center := get_rect_center(destination)
	sin := math.sin(rotation)
	cos := math.cos(rotation)

	x0, y0 := rotate_point(destination.x0, destination.y0, center, cos, sin)
	x1, y1 := rotate_point(destination.x1, destination.y0, center, cos, sin)
	x2, y2 := rotate_point(destination.x1, destination.y1, center, cos, sin)
	x3, y3 := rotate_point(destination.x0, destination.y1, center, cos, sin)

	destination_result: Rect_points = {x0, y0, x1, y1, x2, y2, x3, y3}
	push_quad_points(vertices, destination_result, 1.0, source, {1.0, 1.0, 1.0, 1.0})
}


push_quad_entity :: proc(vertices: ^[dynamic]f32, entity: Entity) {
	destination := Rect {
		x0 = entity.pos.x,
		y0 = entity.pos.y,
		x1 = entity.pos.x + entity.size.x,
		y1 = entity.pos.y + entity.size.y,
	}


	id := entity.asset_id
	source := sprite_table[id]
	level_height := f32(LEVEL_H * TILE_H)
	depth := 0.1 + ((entity.pos.y + entity.size.y) / level_height) * 0.1

	color := entity.color
	push_quad(vertices, destination, depth, source, color)
}


push_quad_tile :: proc(vertices: ^[dynamic]f32, index: int, sprite: Sprite, color: Color) {
	tile_pos := get_tile_pos(u32(index))
	pixel_pos := get_tile_pixel_pos(tile_pos)
	level_height := f32(LEVEL_H) * f32(TILE_H)
	depth: f32 = (f32(pixel_pos.y + TILE_H) / level_height) * 0.1
	destination := Rect {
		x0 = f32(pixel_pos.x),
		y0 = f32(pixel_pos.y),
		x1 = f32(pixel_pos.x) + TILE_W,
		y1 = f32(pixel_pos.y) + TILE_H,
	}
	push_quad(vertices, destination, depth, sprite, color)
}

push_quad :: proc(
	vertices: ^[dynamic]f32,
	destination: Rect,
	depth: f32,
	source: Sprite,
	color: [4]f32,
) {
	//TODO: probably come up with more efficient way of doing this, feels messy
	x0, y0, x1, y1 := destination.x0, destination.y0, destination.x1, destination.y1
	u0, v0, u1, v1 := source.u0, source.v0, source.u1, source.v1
	//TODO: could be fun to make a gradient with two colors
	r, g, b, a := color[0], color[1], color[2], color[3]

	d := depth

	append(vertices, x0, y0, u0, v0, r, g, b, a, d)
	append(vertices, x1, y0, u1, v0, r, g, b, a, d)
	append(vertices, x1, y1, u1, v1, r, g, b, a, d)
	append(vertices, x0, y0, u0, v0, r, g, b, a, d)
	append(vertices, x1, y1, u1, v1, r, g, b, a, d)
	append(vertices, x0, y1, u0, v1, r, g, b, a, d)
}

push_rect :: proc(vertices: ^[dynamic]f32, destination: Rect, depth: f32, color: [4]f32) {
	x0, y0, x1, y1 := destination.x0, destination.y0, destination.x1, destination.y1
	u0, v0, u1, v1: f32 = -1, -1, -1, -1
	r, g, b, a := color[0], color[1], color[2], color[3]

	d := depth

	append(vertices, x0, y0, u0, v0, r, g, b, a, d)
	append(vertices, x1, y0, u1, v0, r, g, b, a, d)
	append(vertices, x1, y1, u1, v1, r, g, b, a, d)
	append(vertices, x0, y0, u0, v0, r, g, b, a, d)
	append(vertices, x1, y1, u1, v1, r, g, b, a, d)
	append(vertices, x0, y1, u0, v1, r, g, b, a, d)
}

push_quad_points :: proc(
	vertices: ^[dynamic]f32,
	destination: Rect_points,
	depth: f32,
	source: Sprite,
	color: [4]f32,
) {
	x0, y0, x1, y1 := destination.x0, destination.y0, destination.x1, destination.y1
	x2, y2, x3, y3 := destination.x2, destination.y2, destination.x3, destination.y3
	u0, v0, u1, v1 := source.u0, source.v0, source.u1, source.v1
	r, g, b, a := color[0], color[1], color[2], color[3]
	d := depth

	append(vertices, x0, y0, u0, v0, r, g, b, a, d)
	append(vertices, x1, y1, u1, v0, r, g, b, a, d)
	append(vertices, x2, y2, u1, v1, r, g, b, a, d)
	append(vertices, x0, y0, u0, v0, r, g, b, a, d)
	append(vertices, x2, y2, u1, v1, r, g, b, a, d)
	append(vertices, x3, y3, u0, v1, r, g, b, a, d)
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
		gl.DrawArrays(gl.TRIANGLES, 0, i32(len(vertices) / 9)) //TODO: change 4 to a variable
		clear(vertices)
	}
}
push_slash_arc :: proc(
	vertices: ^[dynamic]f32,
	center: la.Vector2f32,
	inner_r, outer_r: f32,
	depth: f32,
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

		append(vertices, in0.x, in0.y, -1, -1, r, g, b, a, depth)
		append(vertices, out0.x, out0.y, -1, -1, r, g, b, a, depth)
		append(vertices, out1.x, out1.y, -1, -1, r, g, b, a, depth)
		append(vertices, in0.x, in0.y, -1, -1, r, g, b, a, depth)
		append(vertices, out1.x, out1.y, -1, -1, r, g, b, a, depth)
		append(vertices, in1.x, in1.y, -1, -1, r, g, b, a, depth)
	}
}

push_circle :: proc(
	vertices: ^[dynamic]f32,
	center: la.Vector2f32,
	radius: f32,
	depth: f32,
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

		append(vertices, center.x, center.y, -1, -1, r, g, b, a, depth)
		append(vertices, p0.x, p0.y, -1, -1, r, g, b, a, depth)
		append(vertices, p1.x, p1.y, -1, -1, r, g, b, a, depth)
	}
}

push_ring :: proc(
	vertices: ^[dynamic]f32,
	center: la.Vector2f32,
	inner_r, outer_r: f32,
	depth: f32,
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

		append(vertices, in0.x, in0.y, -1, -1, r, g, b, a, depth)
		append(vertices, out0.x, out0.y, -1, -1, r, g, b, a, depth)
		append(vertices, out1.x, out1.y, -1, -1, r, g, b, a, depth)
		append(vertices, in0.x, in0.y, -1, -1, r, g, b, a, depth)
		append(vertices, out1.x, out1.y, -1, -1, r, g, b, a, depth)
		append(vertices, in1.x, in1.y, -1, -1, r, g, b, a, depth)
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
//TODO: use this
// // shortest signed distance between two angles, handles wraparound at +-PI
// angle_diff :: proc(a, b: f32) -> f32 {
// 	d := b - a
// 	for d > math.PI {d -= math.PI * 2}
// 	for d < -math.PI {d += math.PI * 2}
// 	return d
// }

gl_debug_callback :: proc "c" (
	source: u32,
	type: u32,
	id: u32,
	severity: u32,
	length: i32,
	message: cstring,
	user_param: rawptr,
) {
	context = runtime.default_context()
	log.errorf("GL DEBUG: %s", message)
}
