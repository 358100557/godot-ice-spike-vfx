shader_type particles;
render_mode disable_force;

uniform vec3 acceleration = vec3(0.0);
uniform float drag = 0.0;
uniform float turbulence = 0.0;
uniform float turbulence_speed = 1.0;
uniform float emission_radius = 0.5;
uniform vec3 initial_direction = vec3(0.0, 1.0, 0.0);
uniform float spread = 1.0;
uniform float initial_speed = 1.0;
uniform float speed_scale_min = 0.5;
uniform float speed_scale_max = 1.5;
uniform float size_min = 0.05;
uniform float size_max = 0.1;
uniform float life_seconds_min = 1.0;
uniform float life_seconds_max = 1.0;
uniform vec4 color_a : source_color = vec4(1.0);
uniform vec4 color_b : source_color = vec4(1.0);
uniform float particle_opacity = 1.0;


float hash11(float value) {
	return fract(sin(value * 127.1) * 43758.5453);
}


vec3 random_unit(float seed) {
	float y = hash11(seed + 3.7) * 2.0 - 1.0;
	float angle = hash11(seed + 9.1) * TAU;
	float horizontal = sqrt(max(0.0, 1.0 - y * y));
	return vec3(cos(angle) * horizontal, y, sin(angle) * horizontal);
}


void start() {
	float seed = float(RANDOM_SEED) * 0.000001 + float(INDEX) * 1.618;
	float seed_a = hash11(seed + 1.3);
	float seed_b = hash11(seed + 5.7);
	float angle = seed_a * TAU;
	float radius = sqrt(seed_b) * emission_radius;
	TRANSFORM[3].xyz += vec3(cos(angle) * radius, 0.0, sin(angle) * radius);
	TRANSFORM = EMISSION_TRANSFORM * TRANSFORM;

	vec3 direction = normalize(initial_direction + random_unit(seed + 11.3) * spread);
	if (direction.y < 0.12) {
		direction.y = abs(direction.y) + 0.12;
		direction = normalize(direction);
	}
	VELOCITY = direction * initial_speed * mix(speed_scale_min, speed_scale_max, seed_a);

	CUSTOM.x = 0.0;
	CUSTOM.y = mix(size_min, size_max, seed_b);
	CUSTOM.z = hash11(seed + 17.9);
	float life_seconds = mix(life_seconds_min, life_seconds_max, hash11(seed + 23.1));
	CUSTOM.w = clamp(life_seconds / max(LIFETIME, 0.001), 0.01, 1.0);
	COLOR = mix(color_a, color_b, hash11(seed + 29.7));
	COLOR.a = particle_opacity;
}


void process() {
	float particle_lifetime = max(LIFETIME * max(CUSTOM.w, 0.01), 0.001);
	CUSTOM.x += DELTA / particle_lifetime;
	if (CUSTOM.x >= 1.0) {
		ACTIVE = false;
	} else {
		vec3 position = TRANSFORM[3].xyz;
		float phase = CUSTOM.z * 47.0 + CUSTOM.x * TAU * turbulence_speed;
		vec3 wobble = vec3(
			sin(phase * 1.31 + position.z * 0.55),
			cos(phase * 0.73 + position.x * 0.37) * 0.28,
			cos(phase * 1.17 + position.x * 0.61)
		);

		VELOCITY += (acceleration + wobble * turbulence) * DELTA;
		VELOCITY *= exp(-max(drag, 0.0) * DELTA);
		TRANSFORM[3].xyz += VELOCITY * DELTA;
	}
}
