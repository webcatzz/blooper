@vs vs
in vec2 vert_pos;
in vec2 vert_uv;
out vec2 frag_uv;

layout(binding = 0) uniform vert_uniform {
	vec2 scale_mult;
};

void main() {
	vec2 pos = vert_pos * scale_mult * 2 - 1;
    gl_Position = vec4(pos.x, -pos.y, 0.0, 1.0);
	frag_uv = vert_uv;
}
@end

@fs fs
in vec2 frag_uv;
out vec4 frag_color;

layout(binding = 0) uniform texture2D tex;
layout(binding = 0) uniform sampler smp;

void main() {
    frag_color = texture(sampler2D(tex, smp), frag_uv / textureSize(sampler2D(tex, smp), 0));
}
@end

@program basic vs fs