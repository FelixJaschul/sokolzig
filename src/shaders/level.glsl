#if defined(SOKOL_GLSL)
#version 410
#endif

#if defined(SOKOL_ZIG)
#program level
#endif

#if defined(SOKOL_VERTEX)
in vec3 position;
in vec4 color0;

out vec4 color;

uniform mat4 view_proj;

void main() {
    gl_Position = view_proj * vec4(position, 1.0);
    color = color0;
}
#endif

#if defined(SOKOL_FRAGMENT)
in vec4 color;

out vec4 frag_color;

void main() {
    frag_color = color;
}
#endif
