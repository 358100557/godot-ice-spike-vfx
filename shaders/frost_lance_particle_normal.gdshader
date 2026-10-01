shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform int shape_mode : hint_range(0, 1) = 0;
uniform float end_size : hint_range(0.01, 5.0, 0.01) = 1.0;
uniform float size_in : hint_range(0.001, 0.5, 0.001) = 0.05;
uniform float fade_in : hint_range(0.001, 0.5, 0.001) = 0.08;
uniform float fade_out : hint_range(0.01, 1.0, 0.01) = 0.3;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float spin_amount : hint_range(0.0, 32.0, 0.1) = 0.0;

varying float particle_life;
varying float particle_seed;


void vertex() {
	particle_life = clamp(INSTANCE_CUSTOM.x, 0.0, 1.0);
	particle_seed = INSTANCE_CUSTOM.z;
	float appear = smoothstep(0.0, max(size_in, 0.001), particle_life);
	float size_factor = mix(1.0, end_size, particle_life) * appear;
	VERTEX.xy *= INSTANCE_CUSTOM.y * size_factor;
}


void fragment() {
	vec2 point = UV * 2.0 - 1.0;
	float spin_sign = mix(-1.0, 1.0, step(0.5, fract(particle_seed * 31.7)));
	float angle = particle_seed * TAU + particle_life * spin_amount * spin_sign;
	float cosine = cos(angle);
	float sine = sin(angle);
	point = mat2(vec2(cosine, -sine), vec2(sine, cosine)) * point;

	float mask;
	if (shape_mode == 0) {
		float edge_noise = 0.92 + 0.08 * sin(
			atan(point.y, point.x) * 5.0 + particle_seed * 29.0 + particle_life * 2.0
		);
		float radial = length(point * vec2(0.92, 1.08)) / edge_noise;
		mask = 1.0 - smoothstep(0.18, 1.0, radial);
		mask *= 0.82 + 0.18 * cos(radial * PI * 0.5);
	} else {
		float vertical = abs(point.y);
		float half_width = 0.045 + 0.23 * (1.0 - vertical);
		float horizontal_edge = abs(point.x) / max(half_width, 0.001);
		mask = 1.0 - smoothstep(0.68, 1.0, horizontal_edge);
		mask *= 1.0 - smoothstep(0.88, 1.0, vertical);
	}

	float life_in = smoothstep(0.0, max(fade_in, 0.001), particle_life);
	float life_out = 1.0 - smoothstep(1.0 - fade_out, 1.0, particle_life);
	float alpha = COLOR.a * opacity * mask * life_in * life_out;
	if (alpha < 0.001) {
		discard;
	}

	ALBEDO = COLOR.rgb;
	ALPHA = alpha;
}
