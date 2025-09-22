#version 410
in vec3 position;
in vec4 color0;
out vec4 color;
uniform mat4 view_proj;
void main() {
    gl_Position = view_proj * vec4(position, 1.0);
    color = color0;
}
