shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

uniform float end_size : hint_range(0.01, 1.0, 0.01) = 0.18;
uniform float size_in : hint_range(0.001, 0.5, 0.001) = 0.05;
uniform float fade_in : hint_range(0.001, 0.5, 0.001) = 0.06;
uniform float fade_out : hint_range(0.01, 1.0, 0.01) = 0.35;
uniform float brightness : hint_range(0.0, 5.0, 0.01) = 1.8;

varying float particle_life;
varying float particle_seed;


void vertex() {
	particle_life = clamp(INSTANCE_CUSTOM.x, 0.0, 1.0);
	particle_seed = INSTANCE_CUSTOM.z;
	float appear = smoothstep(0.0, max(size_in, 0.001), particle_life);
	float pulse = 0.88 + 0.12 * sin(particle_seed * 41.0 + particle_life * TAU * 2.0);
	float size_factor = mix(1.0, end_size, particle_life) * appear * pulse;
	VERTEX.xy *= INSTANCE_CUSTOM.y * size_factor;
}


void fragment() {
	vec2 point = UV * 2.0 - 1.0;
	float radial = length(point);
	float core = 1.0 - smoothstep(0.05, 0.82, radial);
	float ray_x = (1.0 - smoothstep(0.03, 0.22, abs(point.x)))
		* (1.0 - smoothstep(0.28, 1.0, abs(point.y)));
	float ray_y = (1.0 - smoothstep(0.03, 0.22, abs(point.y)))
		* (1.0 - smoothstep(0.28, 1.0, abs(point.x)));
	float mask = max(core, max(ray_x, ray_y) * 0.48);

	float life_in = smoothstep(0.0, max(fade_in, 0.001), particle_life);
	float life_out = 1.0 - smoothstep(1.0 - fade_out, 1.0, particle_life);
	float alpha = COLOR.a * mask * life_in * life_out;
	if (alpha < 0.001) {
		discard;
	}

	ALBEDO = COLOR.rgb * brightness;
	EMISSION = COLOR.rgb * brightness;
	ALPHA = alpha;
}
