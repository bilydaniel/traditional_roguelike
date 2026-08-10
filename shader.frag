#version 330 core
in vec2 vTexCoord;
in vec4 vColor;
out vec4 FragColor;
uniform sampler2D uTexture;
void main() {
    vec4 color;
    // depth buffer fix
    //FragColor = texture(uTexture, vTexCoord) * vColor;
    if (vTexCoord.x < 0.0) {
        color = vColor;
    } else {
        color = texture(uTexture, vTexCoord) * vColor;
    }

    if (color.a < 0.01) {
        discard;
    }
    FragColor = color;
}
