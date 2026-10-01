extends Node3D

## Frost Lance Phase 1: procedural crystal geometry, path distribution,
## travelling-front timing, overshoot, hold, and sink. No shaders or particles.

enum Phase {
	IDLE,
	TRAVEL,
	HOLD,
	FADE,
}

const CrystalBuilder = preload("res://scripts/CrystalGeometryBuilder.gd")
const IceShaderControllerScript = preload("res://scripts/IceCrystalShaderController.gd")

const MAX_SPIKES := 288
const VARIANTS := 3
const SLOTS_PER_VARIANT := 96
const TAU := PI * 2.0
const CAST_DIRECTION := Vector3(0.0, 0.0, -1.0)
const UP := Vector3.UP
const VARIANT_SEEDS := [7.3, 29.0, 50.7]

@export_group("Cast")
@export var cast_distance := 15.0
@export var travel_speed := 26.0
@export var spike_count := 190
@export_range(0.0, 1.0, 0.01) var impact_fraction := 0.22

@export_group("Footprint")
@export var width_near := 0.55
@export var width_far := 2.5
@export var width_curve := 0.75
@export var clumping := 1.35
@export var scatter_amount := 0.55
@export var front_bias := 0.85

@export_group("Field Silhouette")
@export var height_near := 0.5
@export var height_far := 3.1
@export var height_curve := 1.7
@export var height_jitter := 0.55
@export var crown := 0.55
@export var peak := 1.45
@export var peak_width := 0.28
@export_range(0.0, 1.0, 0.01) var rubble_probability := 0.42
@export var rubble_scale := 0.3

@export_group("Crystal")
@export var crystal_radius := 0.41
@export var radius_jitter := 0.93
@export var facets := 7
@export var taper := 0.69
@export var roughness := 0.09
@export var bend := 0.66
@export var lean := 0.55
@export var lean_jitter := 1.5
@export var twist := 1.0

@export_group("Ice Shader")
@export var ice_shader_settings: IceCrystalShaderController = IceShaderControllerScript.new()

@export_group("Timing")
@export var rise_time := 0.17
@export var rise_overshoot := 0.26
@export var rise_stagger := 0.09
@export var settle := 0.55
@export var hold_duration := 3.6
@export var sink_delay := 0.6
@export var sink_time := 1.0

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var directional_light: DirectionalLight3D = $DirectionalLight3D
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var ground: MeshInstance3D = $Ground
@onready var variant_nodes: Array[MultiMeshInstance3D] = [
	$FrostLanceFX/Crystals/CrystalVariantA,
	$FrostLanceFX/Crystals/CrystalVariantB,
	$FrostLanceFX/Crystals/CrystalVariantC,
]
@onready var particle_fx: FrostLanceParticles = $FrostLanceFX/Particles
@onready var ground_fx: FrostLanceGroundFX = $FrostLanceFX/GroundFX
@onready var feedback_fx: FrostLanceFeedback = $FrostLanceFX/Feedback
@onready var debug_label: Label = $DebugCanvas/DebugLabel

var phase: int = Phase.IDLE
var records: Array[Dictionary] = []
var multi_meshes: Array[MultiMesh] = []
var rng := RandomNumberGenerator.new()
var ice_material: ShaderMaterial

var active_count := 0
var impact_start := 0
var front := 0.0
var progress := 0.0
var age := 0.0
var hold_time := 0.0
var fade_time := 0.0
var emerged_count := 0

var auto_test := false
var auto_finished := false
var auto_cycles_completed := 0
var captured_travel := false
var captured_hold := false
var captured_sink := false


func _ready() -> void:
	rng.seed = 20260811
	_setup_environment()
	feedback_fx.configure_environment(world_environment.environment)
	_setup_ground()
	_setup_camera()
	_setup_crystal_multimeshes()
	_hide_all_instances()
	_update_debug_label()

	auto_test = "--auto-test" in OS.get_cmdline_user_args()
	print("FROST_LANCE_PHASE1_READY: variants=3 capacity=288")
	if auto_test:
		call_deferred("_spawn_cast")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_SPACE:
			_spawn_cast()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	match phase:
		Phase.TRAVEL:
			_update_travel(delta)
		Phase.HOLD:
			_update_hold(delta)
		Phase.FADE:
			_update_fade(delta)

	_update_debug_label()


func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("111820")
	environment.background_energy_multiplier = 0.85
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8fb7d0")
	environment.ambient_light_energy = 0.42
	world_environment.environment = environment

	directional_light.rotation_degrees = Vector3(-54.0, -28.0, 0.0)
	directional_light.light_color = Color("d9f1ff")
	directional_light.light_energy = 1.65
	directional_light.shadow_enabled = true
	directional_light.directional_shadow_max_distance = 40.0


func _setup_ground() -> void:
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(20.0, 0.12, 24.0)
	ground.mesh = ground_mesh
	ground.position = Vector3(0.0, -0.08, -7.5)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color("202a33")
	material.roughness = 0.92
	ground.material_override = material


func _setup_camera() -> void:
	camera.position = Vector3(8.8, 8.8, 7.8)
	camera.fov = 50.0
	camera.near = 0.1
	camera.far = 80.0
	camera.look_at(Vector3(0.0, 0.9, -7.5), Vector3.UP)


func _setup_crystal_multimeshes() -> void:
	ice_material = ice_shader_settings.create_material()

	for variant_index in range(VARIANTS):
		var mesh: ArrayMesh = CrystalBuilder.build_crystal(
			VARIANT_SEEDS[variant_index],
			facets,
			taper,
			roughness,
			bend
		)
		mesh.surface_set_material(0, ice_material)

		var multi_mesh := MultiMesh.new()
		multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
		multi_mesh.use_custom_data = true
		multi_mesh.instance_count = SLOTS_PER_VARIANT
		multi_mesh.visible_instance_count = 0
		multi_mesh.mesh = mesh

		multi_meshes.append(multi_mesh)
		variant_nodes[variant_index].multimesh = multi_mesh
		variant_nodes[variant_index].material_override = ice_material
		variant_nodes[variant_index].custom_aabb = AABB(
			Vector3(-6.0, -10.0, -18.5),
			Vector3(12.0, 22.0, 21.0)
		)


func _spawn_cast() -> void:
	_build_records()
	particle_fx.begin_cast(active_count)
	ground_fx.begin_cast()
	feedback_fx.begin_cast()
	front = 0.0
	progress = 0.0
	age = 0.0
	hold_time = 0.0
	fade_time = 0.0
	emerged_count = 0
	phase = Phase.TRAVEL
	_set_visible_instance_counts()
	_update_spikes(0.0)
	print(
		"PHASE_TRAVEL: active=%d path=%d impact=%d distance=%.2f speed=%.2f"
		% [active_count, impact_start, active_count - impact_start, cast_distance, travel_speed]
	)


func _build_records() -> void:
	records.clear()
	active_count = mini(MAX_SPIKES, maxi(1, spike_count))
	var impact_count: int = roundi(float(active_count) * impact_fraction)
	impact_start = active_count - impact_count

	for i in range(active_count):
		var is_impact: bool = i >= impact_start
		var record := {
			"along": 1.0 if is_impact else 0.0,
			"lateral": 0.0,
			"scatter": rng.randf_range(-1.0, 1.0),
			"angle": 0.0,
			"radial": 0.0,
			"impact": is_impact,
			"rubble": rng.randf() < rubble_probability,
			"height_jitter": rng.randf_range(-1.0, 1.0),
			"radius_jitter": rng.randf_range(-1.0, 1.0),
			"lean_jitter": rng.randf_range(-1.0, 1.0),
			"yaw": rng.randf_range(0.0, TAU),
			"stagger": rng.randf(),
			"erupt_time": -1.0,
		}

		if is_impact:
			record["angle"] = rng.randf_range(0.0, TAU)
			record["radial"] = sqrt(rng.randf())
		else:
			var stratum: float = (float(i) + rng.randf()) / float(maxi(1, impact_start))
			record["along"] = pow(stratum, front_bias)
			record["lateral"] = rng.randf_range(-1.0, 1.0)

		records.append(record)


func _update_travel(delta: float) -> void:
	age += delta
	var ease_in: float = _out_quad(clampf(age / 0.08, 0.0, 1.0))
	front += travel_speed * ease_in * delta
	var previous_progress := progress
	progress = clampf(front / maxf(0.1, cast_distance), 0.0, 1.0)

	_trigger_up_to(progress, false)
	_update_spikes(0.0)
	particle_fx.emit_travel(
		delta,
		CAST_DIRECTION * minf(front, cast_distance),
		_half_width(progress)
	)
	ground_fx.update_travel(
		front,
		cast_distance,
		CAST_DIRECTION,
		_side(),
		width_near,
		width_far,
		width_curve
	)
	feedback_fx.update_travel(CAST_DIRECTION * minf(front, cast_distance))

	if auto_test and not captured_travel and front >= cast_distance * 0.52:
		captured_travel = true
		_capture_preview("phase1_travel")

	if progress >= 1.0 and previous_progress < 1.0:
		_trigger_up_to(1.0, true)
		particle_fx.emit_impact(CAST_DIRECTION * cast_distance)
		ground_fx.emit_impact(CAST_DIRECTION * cast_distance, _half_width(1.0))
		feedback_fx.emit_impact(CAST_DIRECTION * cast_distance)
		phase = Phase.HOLD
		hold_time = 0.0
		print("PHASE_HOLD: terminal cluster triggered at age=%.3f" % age)


func _update_hold(delta: float) -> void:
	age += delta
	hold_time += delta
	_update_spikes(0.0)
	particle_fx.emit_hold(delta, CAST_DIRECTION, cast_distance, _half_width(1.0))
	feedback_fx.update_hold(hold_time / maxf(hold_duration, 0.001))

	if auto_test and not captured_hold and hold_time >= 0.38:
		captured_hold = true
		_capture_preview("phase1_hold_cluster")

	if hold_time >= hold_duration:
		particle_fx.stop_new_emission()
		phase = Phase.FADE
		fade_time = 0.0
		print("PHASE_FADE: hold completed at age=%.3f" % age)


func _update_fade(delta: float) -> void:
	age += delta
	fade_time += delta
	var retract: float = clampf(
		(fade_time - sink_delay) / maxf(0.05, sink_time),
		0.0,
		1.0
	)
	_update_spikes(retract)
	feedback_fx.update_fade(fade_time / maxf(sink_delay + sink_time, 0.001))

	if auto_test and not captured_sink and retract >= 0.55:
		captured_sink = true
		_capture_preview("phase1_sink")

	if fade_time >= sink_delay + sink_time:
		_finish_cast()


func _finish_cast() -> void:
	feedback_fx.finish_cast()
	phase = Phase.IDLE
	front = 0.0
	progress = 0.0
	emerged_count = 0
	_hide_all_instances()
	print("PHASE_IDLE: cast completed; Space can replay")

	if auto_test:
		auto_cycles_completed += 1
		if auto_cycles_completed < 2:
			print("AUTO_REPLAY: starting second cast through the same reset path")
			call_deferred("_spawn_cast")
		elif not auto_finished:
			auto_finished = true
			_finish_auto_test()


func _trigger_up_to(limit: float, include_impact: bool) -> void:
	for record in records:
		if float(record["erupt_time"]) >= 0.0:
			continue
		if bool(record["impact"]) and not include_impact:
			continue
		if not bool(record["impact"]) and float(record["along"]) > limit:
			continue
		record["erupt_time"] = age + float(record["stagger"]) * rise_stagger


func _update_spikes(retract: float) -> void:
	emerged_count = 0
	for i in range(active_count):
		var record: Dictionary = records[i]
		var variant: int = i % VARIANTS
		var slot: int = int(i / VARIANTS)
		var emergence: float = _emergence(record)
		multi_meshes[variant].set_instance_custom_data(
			slot,
			Color(_shader_seed(i), _birth_glow(record), 0.0, 1.0)
		)

		if emergence < 0.0:
			var buried_transform := Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * 0.0001),
				Vector3(0.0, -999.0, 0.0)
			)
			multi_meshes[variant].set_instance_transform(slot, buried_transform)
			continue

		emerged_count += 1
		var height: float = _spike_height(record)
		var radius: float = _spike_radius(record)
		var spike_position: Vector3 = _spike_position(record)
		particle_fx.emit_breach(
			i,
			emergence,
			Vector3(spike_position.x, 0.08, spike_position.z),
			radius,
			CAST_DIRECTION
		)
		spike_position.y = (emergence - 1.0) * height * 0.85

		if retract > 0.0:
			var sink: float = _in_cubic(retract)
			spike_position.y -= sink * (height + radius + 0.4)

		var outward: float
		if bool(record["impact"]):
			outward = signf(cos(float(record["angle"]))) * float(record["radial"])
		else:
			outward = _lateral_norm(record)

		var lean_direction: Vector3 = (
			CAST_DIRECTION * 0.75 + _side() * outward * 0.85
		)
		if lean_direction.length_squared() < 0.000001:
			lean_direction = CAST_DIRECTION
		lean_direction = lean_direction.normalized()

		var lean_angle: float = (
			lean
			* (0.35 + 0.65 * float(record["along"]))
			* (1.0 + float(record["lean_jitter"]) * lean_jitter)
		)
		var lean_axis: Vector3 = UP.cross(lean_direction).normalized()
		var tilt := Quaternion(lean_axis, lean_angle)
		var spin := Quaternion(UP, float(record["yaw"]) * twist)
		var rotation := tilt * spin

		var settled: float = clampf(emergence, 0.0, 1.0)
		var scale_multiplier: float = lerpf(0.86, 1.0, settled)
		var instance_scale := Vector3(radius, height, radius) * scale_multiplier
		var instance_transform := Transform3D(
			Basis(rotation).scaled_local(instance_scale),
			spike_position
		)
		multi_meshes[variant].set_instance_transform(slot, instance_transform)


func _birth_glow(record: Dictionary) -> float:
	var erupt_time: float = float(record["erupt_time"])
	if erupt_time < 0.0:
		return 0.0
	var elapsed: float = age - erupt_time
	if elapsed < 0.0:
		return 0.0
	return clampf(
		1.0 - elapsed / maxf(0.01, ice_shader_settings.birth_fade),
		0.0,
		1.0
	)


static func _shader_seed(instance_index: int) -> float:
	var value: float = sin((float(instance_index) + 1.0) * 12.9898) * 43758.5453
	return value - floor(value)


func _emergence(record: Dictionary) -> float:
	var erupt_time: float = float(record["erupt_time"])
	if erupt_time < 0.0:
		return -1.0

	var elapsed: float = age - erupt_time
	if elapsed < 0.0:
		return -1.0

	var safe_rise_time: float = maxf(0.02, rise_time)
	var rise: float = _out_quint(clampf(elapsed / safe_rise_time, 0.0, 1.0))
	if elapsed <= safe_rise_time:
		return rise

	var after: float = elapsed - safe_rise_time
	var spring: float = sin(after * 14.0) * exp(-after / maxf(0.05, settle))
	return 1.0 + rise_overshoot * spring


func _spike_position(record: Dictionary) -> Vector3:
	if bool(record["impact"]):
		var reach: float = _half_width(1.0) * 1.25 * float(record["radial"])
		var terminal := CAST_DIRECTION * cast_distance
		terminal.x += cos(float(record["angle"])) * reach
		terminal.z += sin(float(record["angle"])) * reach
		return terminal

	return (
		CAST_DIRECTION * float(record["along"]) * cast_distance
		+ _side()
		* _lateral_norm(record)
		* _half_width(float(record["along"]))
	)


func _spike_height(record: Dictionary) -> float:
	var along: float = float(record["along"])
	var height: float = lerpf(height_near, height_far, pow(clampf(along, 0.0, 1.0), height_curve))
	height *= 1.0 + (peak - 1.0) * _smoothstep(1.0 - peak_width, 1.0, along)

	var edge: float
	if bool(record["impact"]):
		edge = float(record["radial"])
	else:
		edge = clampf(absf(_lateral_norm(record)), 0.0, 1.0)
	height *= lerpf(1.0, 1.0 - clampf(crown, 0.0, 1.0), pow(edge, 1.4))

	height *= 1.0 + float(record["height_jitter"]) * height_jitter
	if bool(record["rubble"]):
		height *= rubble_scale
	return maxf(0.02, height)


func _spike_radius(record: Dictionary) -> float:
	var along: float = float(record["along"])
	var grow: float = lerpf(0.72, 1.15, pow(clampf(along, 0.0, 1.0), 0.6))
	var jitter: float = 1.0 + float(record["radius_jitter"]) * radius_jitter
	var radius: float = crystal_radius * grow * jitter
	if bool(record["rubble"]):
		radius *= 1.25
	return maxf(0.01, radius)


func _half_width(along: float) -> float:
	return lerpf(width_near, width_far, pow(clampf(along, 0.0, 1.0), width_curve))


func _lateral_norm(record: Dictionary) -> float:
	var raw: float = float(record["lateral"])
	var clumped: float = signf(raw) * pow(absf(raw), clumping)
	return clumped + float(record["scatter"]) * scatter_amount


func _side() -> Vector3:
	return CAST_DIRECTION.cross(UP).normalized()


func _set_visible_instance_counts() -> void:
	for variant in range(VARIANTS):
		var count_for_variant := 0
		for i in range(active_count):
			if i % VARIANTS == variant:
				count_for_variant += 1
		multi_meshes[variant].visible_instance_count = count_for_variant


func _hide_all_instances() -> void:
	for multi_mesh in multi_meshes:
		multi_mesh.visible_instance_count = 0


func _update_debug_label() -> void:
	debug_label.text = (
		"Frost Lance Phase 1\n"
		+ "Space: Spawn / Replay\n"
		+ "Phase: %s\n" % _phase_name()
		+ "Active Crystals: %d / %d\n" % [emerged_count, active_count]
		+ "Front Distance: %.2f / %.2f m" % [minf(front, cast_distance), cast_distance]
	)


func _phase_name() -> String:
	match phase:
		Phase.TRAVEL:
			return "TRAVEL"
		Phase.HOLD:
			return "HOLD"
		Phase.FADE:
			return "FADE"
		_:
			return "IDLE"


func _capture_preview(file_stem: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.qa"))
	var output_path: String = ProjectSettings.globalize_path("res://.qa/%s.png" % file_stem)
	var error: Error = image.save_png(output_path)
	print("QA_CAPTURE: %s error=%d" % [output_path, error])


func _finish_auto_test() -> void:
	await get_tree().create_timer(0.25).timeout
	print(
		"AUTO_TEST_PASS: cycles=%d travel=%s hold=%s sink=%s records=%d variants=%d"
		% [auto_cycles_completed, captured_travel, captured_hold, captured_sink, records.size(), multi_meshes.size()]
	)
	get_tree().quit()


static func _out_quad(value: float) -> float:
	return 1.0 - (1.0 - value) * (1.0 - value)


static func _out_quint(value: float) -> float:
	return 1.0 - pow(1.0 - value, 5.0)


static func _in_cubic(value: float) -> float:
	return value * value * value


static func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 0.0
	var t: float = clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
