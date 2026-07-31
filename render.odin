package main

import "base:runtime"
import "core:fmt"
import "core:log"
import la "core:math/linalg"
import "core:os"
import "core:strings"
import gl "vendor:OpenGL"
import "vendor:glfw"
import stbi "vendor:stb/image"

TARGET_FPS :: 144
FRAME_TIME :: 1.0 / TARGET_FPS

Renderer :: struct {
	window:   glfw.WindowHandle,
	camera:   Camera,
	vao:      u32,
	vbo:      u32,
	texture:  u32,
	u_res:    i32,
	u_tex:    i32,
	u_cam:    i32,
	u_zoom:   i32,
	//TODO: probably split vertices onto its own arena, reset every frame
	vertices: [dynamic]f32,
}

init_renderer :: proc() -> (renderer: Renderer, ok: bool) {
	if !glfw.Init() {
		log.error("glfw init failed")
		return
	}

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

	window := glfw.CreateWindow(800, 600, "Traditional Roguelike", nil, nil)
	if window == nil {
		log.error("failed to create window")
		return
	}

	renderer.window = window

	glfw.MakeContextCurrent(window)
	glfw.SwapInterval(0) // vsync off

	gl.load_up_to(3, 3, glfw.gl_set_proc_address)

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

	vertex_attrib_floats := 8
	stride := i32(vertex_attrib_floats * size_of(f32))
	gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, stride, uintptr(0))
	gl.EnableVertexAttribArray(0) // aPos
	gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, stride, uintptr(2 * size_of(f32))) // aTexCoord
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(2, 4, gl.FLOAT, gl.FALSE, stride, uintptr(4 * size_of(f32))) // aColor
	gl.EnableVertexAttribArray(2)

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

	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, texture)

	renderer.u_res = gl.GetUniformLocation(shader_program.id, "uResolution")
	renderer.u_tex = gl.GetUniformLocation(shader_program.id, "uTexture")

	renderer.u_cam = gl.GetUniformLocation(shader_program.id, "uCam")
	renderer.u_zoom = gl.GetUniformLocation(shader_program.id, "uZoom")

	ok = true
	return
}

Camera :: struct {
	pos:       la.Vector2f32,
	zoom:      f32,
	smoothing: f32,
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
