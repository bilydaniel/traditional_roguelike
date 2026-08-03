#version 330 core

layout(location = 0) in vec2 aPos;
layout(location = 1) in vec2 aTexCoord;
layout(location = 2) in vec4 aColor;
layout(location = 3) in float aDepth;

uniform vec2 uResolution;
uniform vec2 uCam;
uniform float uZoom;
uniform float uWorldHeight;

out vec2 vTexCoord;
out vec4 vColor;

void main() {
    vec2 screen = (aPos - uCam) * uZoom;
    vec2 ndc = (screen / uResolution) * 2.0 - 1.0; // 0 -> 1
    ndc.y = -ndc.y;
    //gl_Position = vec4(ndc, 0.0, 1.0);
    float z = 1.0 - (aDepth / uWorldHeight) * 2;
    gl_Position = vec4(ndc, z, 1.0);
    vTexCoord = aTexCoord;
    vColor = aColor;
}
