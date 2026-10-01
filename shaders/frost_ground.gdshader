shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

uniform vec4 color_frost : source_color = vec4(0.973, 0.992, 1.0, 1.0);
uniform vec4 color_edge : source_color = vec4(0.612, 0.847, 0.929, 1.0);
uniform float effect_age : hint_range(0.0, 1.0, 0.001) = 0.0;
uniform float seed = 0.0;
uniform float intensity : hint_range(0.0, 2.0, 0.01) = 0.85;


// Independently designed for this VFX: quantized coordinates, unsigned mixing.
// Retain fractional seeds; take 24 result bits to guarantee a value below 1.0.
float lattice_random_2d(vec2 value) {
	uvec2 coordinate = uvec2(ivec2(floor(value * 256.0)));
	uint mixed = coordinate.x * 1459277413u + coordinate.y * 3472864199u;
	mixed = mixed ^ (mixed >> 13u);
	mixed = mixed * 1266479903u;
	mixed = mixed ^ (mixed >> 16u);
	mixed = mixed * 2659756219u;
	mixed = mixed ^ (mixed >> 15u);
	return float(mixed >> 8u) * (1.0 / 16777216.0);
}


float noise2(vec2 position) {
	vec2 cell = floor(position);
	vec2 local = fract(position);
	vec2 curve = local * local * (3.0 - 2.0 * local);
	float a = lattice_random_2d(cell);
	float b = lattice_random_2d(cell + vec2(1.0, 0.0));
	float c = lattice_random_2d(cell + vec2(0.0, 1.0));
	float d = lattice_random_2d(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, curve.x), mix(c, d, curve.x), curve.y);
}


float fbm2(vec2 position) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 4; octave++) {
		value += noise2(position) * amplitude;
		position = position * 2.03 + vec2(5.7, 9.2);
		amplitude *= 0.5;
	}
	return value / 0.9375;
}


float voronoi2(vec2 position) {
	vec2 cell = floor(position);
	vec2 local = fract(position);
	float nearest = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 point = offset + vec2(
				lattice_random_2d(cell + offset + seed),
				lattice_random_2d(cell + offset + seed + 19.7)
			);
			nearest = min(nearest, length(point - local));
		}
	}
	return nearest;
}


void fragment() {
	vec2 point = UV * 2.0 - 1.0;
	float angle = seed * 6.283185;
	point = mat2(
		vec2(cos(angle), -sin(angle)),
		vec2(sin(angle), cos(angle))
	) * point;

	float age = clamp(effect_age, 0.0, 1.0);
	float growth = mix(0.035, 1.0, pow(age, 0.30));
	float radial = length(point * vec2(0.94, 1.06)) / max(growth, 0.001);

	float broad_noise = fbm2(point * 2.15 + vec2(seed * 31.0));
	float mid_noise = fbm2(point * 6.4 + vec2(seed * 47.0));
	float grain = fbm2(point * 19.0 + vec2(seed * 71.0));
	float cells = voronoi2(point * 5.8 + vec2(seed * 13.0));
	float crystal_cells = voronoi2(point * 14.0 + vec2(seed * 89.0));
	float irregular_radius = 0.81 + (broad_noise - 0.5) * 0.32 + (cells - 0.42) * 0.11;
	float coverage = 1.0 - smoothstep(irregular_radius - 0.16, irregular_radius + 0.04, radial);

	float frozen_mass = smoothstep(0.28, 0.68, broad_noise * 0.58 + mid_noise * 0.42);
	float crystal = 1.0 - smoothstep(0.18, 0.50, crystal_cells);
	float breakup = smoothstep(0.14, 0.56, grain + frozen_mass * 0.24 + coverage * 0.18);
	coverage *= mix(0.76, 1.0, breakup);

	float normalized_radius = radial / max(irregular_radius, 0.001);
	float edge = smoothstep(0.20, 0.90, normalized_radius);
	float white_core = 1.0 - smoothstep(0.16, 0.82, normalized_radius);
	vec3 frost_color = mix(color_frost.rgb, color_edge.rgb, edge * 0.56);
	frost_color = mix(frost_color, vec3(1.0), white_core * (0.20 + frozen_mass * 0.16));
	frost_color = mix(frost_color, color_frost.rgb, crystal * 0.20);
	frost_color *= 0.94 + mid_noise * 0.12 + crystal * 0.06;

	float appear = smoothstep(0.0, 0.055, age);
	float fade = 1.0 - smoothstep(0.55, 1.0, age);
	float density = mix(0.82, 1.0, frozen_mass) * mix(0.90, 1.0, crystal);
	float alpha = coverage * density * appear * fade * intensity * 0.64;
	if (alpha < 0.001) {
		discard;
	}

	ALBEDO = frost_color;
	EMISSION = frost_color * (white_core * 0.035 + crystal * 0.085);
	ALPHA = alpha;
}
