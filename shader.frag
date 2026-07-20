#version 330 core
in vec2 vTexCoord;
in vec4 vColor;
out vec4 FragColor;
uniform sampler2D uTexture;
void main() {
    FragColor = texture(uTexture, vTexCoord) * vColor;
}
