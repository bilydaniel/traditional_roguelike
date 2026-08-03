#version 330 core

layout(location = 0) in vec2 aPos;
layout(location = 1) in vec2 aTexCoord;
layout(location = 2) in vec4 aColor;

uniform vec2 uResolution;
uniform vec2 uCam;
uniform float uZoom;

out vec2 vTexCoord;
out vec4 vColor;

void main() {
    vec2 screen = (aPos - uCam) * uZoom;
    vec2 ndc = (screen / uResolution) * 2.0 - 1.0; // 0 -> 1
    ndc.y = -ndc.y;
    //gl_Position = vec4(ndc, 0.0, 1.0);
    gl_Position = vec4(ndc, 0.0, 1.0);
    vTexCoord = aTexCoord;
    vColor = aColor;
}
