#version 330 core
in vec2 vTexCoord;
in vec4 vColor;
out vec4 FragColor;
uniform sampler2D uTexture;
void main() {
    // depth buffer fix
    // if (vColor.a < 0.01) {
    //     discard;
    // }
    //FragColor = texture(uTexture, vTexCoord) * vColor;
    if (vTexCoord.x < 0.0) {
        FragColor = vColor;
    } else {
        FragColor = texture(uTexture, vTexCoord) * vColor;
    }
}
