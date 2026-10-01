class_name FrostLanceParticles
extends Node3D

## Phase 3-only particle setup and emission for the Compatibility renderer.
## Geometry, crystal transforms, Phase 1 timing, and Phase 2 material values are
## intentionally outside this controller.

const PROCESS_SHADER: Shader = preload("res://shaders/frost_lance_particle_process.gdshader")
const NORMAL_SHADER: Shader = preload("res://shaders/frost_lance_particle_normal.gdshader")
const GLITTER_SHADER: Shader = preload("res://shaders/frost_lance_particle_glitter.gdshader")

const MIST_CAPACITY := 3200
const SHARD_CAPACITY := 2400
const GLITTER_CAPACITY := 2800

const MIST_FRONT_RATE := 260.0
const GLITTER_FRONT_RATE := 130.0
const GLITTER_HOLD_RATE := 45.5
const IMPACT_WINDOW := 0.18

@onready var mist: GPUParticles3D = $Mist
@onready var shards: GPUParticles3D = $Shards
@onready var glitter: GPUParticles3D = $Glitter

var mist_process: ShaderMaterial
var shard_process: ShaderMaterial
var glitter_process: ShaderMaterial
var rng := RandomNumberGenerator.new()

var breached := PackedByteArray()
var pending_breach_count := 0
var pending_breach_position := Vector3.ZERO
var pending_breach_radius := 0.0
var shard_activity_time := 0.0
var impact_time := 0.0
var hold_profile_active := false


func _ready() -> void:
	rng.seed = 20260813
	_configure_mist()
	_configure_shards()
	_configure_glitter()


func begin_cast(instance_count: int) -> void:
	rng.seed = 20260813
	breached.resize(instance_count)
	breached.fill(0)
	pending_breach_count = 0
	pending_breach_position = Vector3.ZERO
	pending_breach_radius = 0.0
	shard_activity_time = 0.0
	impact_time = 0.0
	hold_profile_active = false
	stop_new_emission()
	_set_mist_travel_profile(0.5)
	_set_shard_breach_profile(0.2)
	_set_glitter_travel_profile(0.5)


func emit_travel(delta: float, front_position: Vector3, half_width: float) -> void:
	mist.position = front_position
	glitter.position = front_position
	mist_process.set_shader_parameter("emission_radius", maxf(0.05, half_width * 0.9))
	glitter_process.set_shader_parameter("emission_radius", maxf(0.05, half_width))
	_set_rate(mist, MIST_FRONT_RATE)
	_set_rate(glitter, GLITTER_FRONT_RATE)
	mist.emitting = true
	glitter.emitting = true
	_update_breach_emission(delta, false)


func emit_breach(
	instance_index: int,
	emergence: float,
	position: Vector3,
	radius: float,
	cast_direction: Vector3
) -> void:
	if emergence <= 0.25:
		return
	if instance_index < 0 or instance_index >= breached.size():
		return
	if breached[instance_index] != 0:
		return
	breached[instance_index] = 1
	pending_breach_count += 1
	pending_breach_position += position
	pending_breach_radius = maxf(pending_breach_radius, radius * 0.8)
	shard_process.set_shader_parameter(
		"initial_direction",
		(cast_direction * 0.35 + Vector3.UP).normalized()
	)


func emit_impact(position: Vector3) -> void:
	var impact_position := position
	impact_position.y = 0.4
	impact_time = IMPACT_WINDOW
	hold_profile_active = false

	mist.position = impact_position
	shards.position = impact_position
	glitter.position = impact_position

	_set_process_profile(
		mist_process,
		2.0,
		Vector3.UP,
		1.0,
		3.12,
		0.45,
		1.45,
		0.85,
		1.20,
		3.5,
		4.2,
		Color("789eac"),
		Color("d9f7ff"),
		0.034
	)
	_set_process_profile(
		shard_process,
		2.0,
		Vector3.UP,
		0.9,
		12.6,
		0.35,
		1.65,
		0.060,
		0.115,
		1.8,
		2.4,
		Color("8adaff"),
		Color("f2feff"),
		0.94
	)
	_set_process_profile(
		glitter_process,
		2.0,
		Vector3.UP,
		0.8,
		5.44,
		0.35,
		1.65,
		0.038,
		0.070,
		2.7,
		3.4,
		Color("a9e9ff"),
		Color("ffffff"),
		0.92
	)

	_set_rate(mist, 90.0 / IMPACT_WINDOW)
	_set_rate(shards, 90.0 / IMPACT_WINDOW)
	_set_rate(glitter, 150.0 / IMPACT_WINDOW)
	mist.emitting = true
	shards.emitting = true
	glitter.emitting = true


func emit_hold(
	delta: float,
	cast_direction: Vector3,
	cast_distance: float,
	half_width_far: float
) -> void:
	impact_time = maxf(0.0, impact_time - delta)
	_update_breach_emission(delta, impact_time > 0.0)

	if impact_time > 0.0:
		return

	if not hold_profile_active:
		hold_profile_active = true
		mist.emitting = false
		_set_shard_breach_profile(maxf(0.05, half_width_far * 0.25))
		_set_glitter_hold_profile(half_width_far)
		_set_rate(glitter, GLITTER_HOLD_RATE)
		glitter.emitting = true

	var along := rng.randf_range(0.25, 1.0)
	glitter.position = cast_direction * cast_distance * along
	glitter.position.y = 0.35
	glitter_process.set_shader_parameter("emission_radius", maxf(0.05, half_width_far))


func stop_new_emission() -> void:
	mist.emitting = false
	shards.emitting = false
	glitter.emitting = false


func _update_breach_emission(delta: float, impact_active: bool) -> void:
	if pending_breach_count > 0:
		shards.position = pending_breach_position / float(pending_breach_count)
		shard_process.set_shader_parameter(
			"emission_radius",
			maxf(0.03, pending_breach_radius)
		)
		shard_activity_time = 0.06
		if not impact_active:
			var requested_rate := float(pending_breach_count * 3) / maxf(delta, 0.001)
			_set_rate(shards, clampf(requested_rate, 350.0, 1000.0))
			shards.emitting = true

		pending_breach_count = 0
		pending_breach_position = Vector3.ZERO
		pending_breach_radius = 0.0
	else:
		shard_activity_time = maxf(0.0, shard_activity_time - delta)

	if not impact_active and shard_activity_time <= 0.0:
		shards.emitting = false


func _configure_mist() -> void:
	_configure_system(mist, MIST_CAPACITY, 4.2)
	mist_process = _process_material(Vector3(0.0, 0.35, 0.0), 1.9, 0.4, 1.0)
	mist.process_material = mist_process
	mist.draw_pass_1 = _normal_quad(0, 2.7, 0.10, 0.14, 0.30, 1.0, 0.5)


func _configure_shards() -> void:
	_configure_system(shards, SHARD_CAPACITY, 2.4)
	shard_process = _process_material(Vector3(0.0, -14.0, 0.0), 0.22, 0.08, 1.4)
	shards.process_material = shard_process
	shards.draw_pass_1 = _normal_quad(1, 0.85, 0.025, 0.025, 0.72, 1.0, 16.0)


func _configure_glitter() -> void:
	_configure_system(glitter, GLITTER_CAPACITY, 3.4)
	glitter_process = _process_material(Vector3(0.0, 1.6, 0.0), 1.1, 0.55, 1.25)
	glitter.process_material = glitter_process
	glitter.draw_pass_1 = _glitter_quad()


func _configure_system(system: GPUParticles3D, capacity: int, maximum_lifetime: float) -> void:
	system.emitting = false
	system.one_shot = false
	system.amount = capacity
	system.amount_ratio = 0.0
	system.lifetime = maximum_lifetime
	system.local_coords = false
	system.fixed_fps = 30
	system.fract_delta = true
	system.interpolate = true
	system.draw_passes = 1
	system.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	system.visibility_aabb = AABB(
		Vector3(-12.0, -8.0, -23.0),
		Vector3(24.0, 24.0, 31.0)
	)


func _process_material(
	acceleration: Vector3,
	drag: float,
	turbulence: float,
	turbulence_speed: float
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PROCESS_SHADER
	material.set_shader_parameter("acceleration", acceleration)
	material.set_shader_parameter("drag", drag)
	material.set_shader_parameter("turbulence", turbulence)
	material.set_shader_parameter("turbulence_speed", turbulence_speed)
	return material


func _set_mist_travel_profile(radius: float) -> void:
	_set_process_profile(
		mist_process,
		radius,
		Vector3.UP,
		1.0,
		1.3,
		0.3,
		1.7,
		0.55,
		0.95,
		2.2,
		3.2,
		Color("789eac"),
		Color("c6edf5"),
		0.06
	)


func _set_shard_breach_profile(radius: float) -> void:
	_set_process_profile(
		shard_process,
		radius,
		(Vector3(0.0, 1.0, -0.35)).normalized(),
		1.0,
		7.0,
		0.3,
		1.7,
		0.025,
		0.080,
		1.3,
		2.1,
		Color("8adaff"),
		Color("f2feff"),
		0.88
	)


func _set_glitter_travel_profile(radius: float) -> void:
	_set_process_profile(
		glitter_process,
		radius,
		Vector3.UP,
		0.85,
		3.4,
		0.2,
		1.8,
		0.025,
		0.052,
		2.0,
		3.0,
		Color("a9e9ff"),
		Color("f2feff"),
		0.82
	)


func _set_glitter_hold_profile(radius: float) -> void:
	_set_process_profile(
		glitter_process,
		radius,
		Vector3.UP,
		0.9,
		2.38,
		0.2,
		1.8,
		0.022,
		0.046,
		2.0,
		3.0,
		Color("a9e9ff"),
		Color("f2feff"),
		0.72
	)


func _set_process_profile(
	material: ShaderMaterial,
	emission_radius: float,
	direction: Vector3,
	spread: float,
	speed: float,
	speed_min: float,
	speed_max: float,
	size_min: float,
	size_max: float,
	life_min: float,
	life_max: float,
	color_a: Color,
	color_b: Color,
	opacity: float
) -> void:
	material.set_shader_parameter("emission_radius", emission_radius)
	material.set_shader_parameter("initial_direction", direction)
	material.set_shader_parameter("spread", spread)
	material.set_shader_parameter("initial_speed", speed)
	material.set_shader_parameter("speed_scale_min", speed_min)
	material.set_shader_parameter("speed_scale_max", speed_max)
	material.set_shader_parameter("size_min", size_min)
	material.set_shader_parameter("size_max", size_max)
	material.set_shader_parameter("life_seconds_min", life_min)
	material.set_shader_parameter("life_seconds_max", life_max)
	material.set_shader_parameter("color_a", color_a)
	material.set_shader_parameter("color_b", color_b)
	material.set_shader_parameter("particle_opacity", opacity)


func _set_rate(system: GPUParticles3D, particles_per_second: float) -> void:
	var maximum_rate := float(system.amount) / maxf(system.lifetime, 0.001)
	system.amount_ratio = clampf(particles_per_second / maximum_rate, 0.0, 1.0)


func _normal_quad(
	shape_mode: int,
	end_size: float,
	size_in: float,
	fade_in: float,
	fade_out: float,
	opacity: float,
	spin_amount: float
) -> QuadMesh:
	var material := ShaderMaterial.new()
	material.shader = NORMAL_SHADER
	material.set_shader_parameter("shape_mode", shape_mode)
	material.set_shader_parameter("end_size", end_size)
	material.set_shader_parameter("size_in", size_in)
	material.set_shader_parameter("fade_in", fade_in)
	material.set_shader_parameter("fade_out", fade_out)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("spin_amount", spin_amount)

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	return quad


func _glitter_quad() -> QuadMesh:
	var material := ShaderMaterial.new()
	material.shader = GLITTER_SHADER
	material.set_shader_parameter("end_size", 0.18)
	material.set_shader_parameter("size_in", 0.05)
	material.set_shader_parameter("fade_in", 0.06)
	material.set_shader_parameter("fade_out", 0.35)
	material.set_shader_parameter("brightness", 1.8)

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	return quad
