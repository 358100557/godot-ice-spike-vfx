class_name FrostLanceGroundFX
extends Node3D

## Phase 4-only Ground FX. Existing crystal, material, particle, camera, and
## timing parameters are consumed read-only through the minimal root wiring.

const FROST_SHADER: Shader = preload("res://shaders/frost_ground.gdshader")
const SHOCKWAVE_SHADER: Shader = preload("res://shaders/frost_shockwave.gdshader")
const BURST_SHADER: Shader = preload("res://shaders/frost_burst.gdshader")

const PATCH_POOL_SIZE := 128
const FROST_RATE := 3.6
const FROST_STEP := 1.0 / FROST_RATE
const FROST_SPREAD := 1.35
const PATH_FROST_LIFE := 7.0
const IMPACT_FROST_LIFE := 9.1
const SHOCKWAVE_LIFE := 0.75
const BURST_LIFE := 0.95
const FROST_RENDER_PRIORITY := -10

@onready var frost_patch_pool: Node3D = $FrostPatchPool
@onready var impact_frost: MeshInstance3D = $ImpactFrost
@onready var shockwave: MeshInstance3D = $Shockwave
@onready var frost_burst: MeshInstance3D = $"../ImpactFX/FrostBurst"

var rng := RandomNumberGenerator.new()
var patch_mesh: QuadMesh
var patch_nodes: Array[MeshInstance3D] = []
var patch_materials: Array[ShaderMaterial] = []
var patch_ages := PackedFloat32Array()
var patch_lifetimes := PackedFloat32Array()
var patch_active := PackedByteArray()
var patch_cursor := 0
var frost_distance := 0.0

var impact_material: ShaderMaterial
var impact_age := 0.0
var impact_active := false

var shockwave_material: ShaderMaterial
var shockwave_age := 0.0
var shockwave_active := false

var burst_material: ShaderMaterial
var burst_age := 0.0
var burst_active := false


func _ready() -> void:
	rng.seed = 20260814
	_setup_patch_pool()
	_setup_impact_frost()
	_setup_shockwave()
	_setup_frost_burst()


func _process(delta: float) -> void:
	_update_path_patches(delta)
	_update_impact_frost(delta)
	_update_shockwave(delta)
	_update_frost_burst(delta)


func begin_cast() -> void:
	rng.seed = 20260814
	frost_distance = 0.0


func update_travel(
	current_front: float,
	cast_distance: float,
	cast_direction: Vector3,
	side: Vector3,
	width_near: float,
	width_far: float,
	width_curve: float
) -> void:
	var clamped_front := minf(current_front, cast_distance)
	while clamped_front - frost_distance >= FROST_STEP:
		frost_distance += FROST_STEP
		var along := clampf(frost_distance / maxf(cast_distance, 0.001), 0.0, 1.0)
		var half_width := lerpf(width_near, width_far, pow(along, width_curve))
		var lateral_offset := rng.randf_range(-0.7, 0.7) * half_width
		var position := cast_direction * frost_distance + side * lateral_offset
		position.y = -0.012 + rng.randf_range(0.0, 0.002)
		var radius := half_width * FROST_SPREAD * rng.randf_range(0.6, 1.15)
		var path_frost_strength := 1.0
		if along <= 0.35:
			path_frost_strength = lerpf(0.48, 0.62, smoothstep(0.0, 0.35, along))
		elif along < 0.65:
			path_frost_strength = lerpf(0.62, 1.0, smoothstep(0.35, 0.65, along))
		_spawn_path_patch(position, radius, path_frost_strength)


func emit_impact(position: Vector3, half_width_far: float) -> void:
	var ground_position := position
	ground_position.y = 0.016
	var impact_radius := half_width_far * FROST_SPREAD * 2.2
	_spawn_impact_frost(ground_position, impact_radius)
	_spawn_shockwave(ground_position, 5.5)

	var burst_position := position
	burst_position.y = 0.6
	_spawn_frost_burst(burst_position)


func _setup_patch_pool() -> void:
	patch_mesh = QuadMesh.new()
	patch_mesh.size = Vector2.ONE
	patch_ages.resize(PATCH_POOL_SIZE)
	patch_lifetimes.resize(PATCH_POOL_SIZE)
	patch_active.resize(PATCH_POOL_SIZE)
	patch_active.fill(0)

	for i in range(PATCH_POOL_SIZE):
		var node := MeshInstance3D.new()
		node.name = "FrostPatch%03d" % i
		node.mesh = patch_mesh
		node.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		node.visible = false
		frost_patch_pool.add_child(node)

		var material := ShaderMaterial.new()
		material.shader = FROST_SHADER
		material.render_priority = FROST_RENDER_PRIORITY
		material.set_shader_parameter("color_frost", Color("f8fdff"))
		material.set_shader_parameter("color_edge", Color("9cd8ed"))
		node.material_override = material

		patch_nodes.append(node)
		patch_materials.append(material)


func _setup_impact_frost() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	impact_frost.mesh = mesh
	impact_frost.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	impact_frost.visible = false

	impact_material = ShaderMaterial.new()
	impact_material.shader = FROST_SHADER
	impact_material.render_priority = FROST_RENDER_PRIORITY
	impact_material.set_shader_parameter("color_frost", Color("f8fdff"))
	impact_material.set_shader_parameter("color_edge", Color("9cd8ed"))
	impact_frost.material_override = impact_material


func _setup_shockwave() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	shockwave.mesh = mesh
	shockwave.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	shockwave.visible = false

	shockwave_material = ShaderMaterial.new()
	shockwave_material.shader = SHOCKWAVE_SHADER
	shockwave_material.set_shader_parameter("color_inner", Color("5fd0ff"))
	shockwave_material.set_shader_parameter("color_outer", Color("f2feff"))
	shockwave_material.set_shader_parameter("maximum_radius", 5.5)
	shockwave_material.set_shader_parameter("ring_width", 0.06)
	shockwave_material.set_shader_parameter("intensity", 0.9)
	shockwave.material_override = shockwave_material


func _setup_frost_burst() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	frost_burst.mesh = mesh
	frost_burst.visible = false

	burst_material = ShaderMaterial.new()
	burst_material.shader = BURST_SHADER
	burst_material.set_shader_parameter("burst_color", Color("a6e6ff"))
	burst_material.set_shader_parameter("rim_color", Color("f2feff"))
	burst_material.set_shader_parameter("intensity", 0.75)
	burst_material.set_shader_parameter("opacity", 0.85)
	burst_material.set_shader_parameter("fresnel_power", 1.3)
	burst_material.set_shader_parameter("displace", 0.55)
	frost_burst.material_override = burst_material


func _spawn_path_patch(position: Vector3, radius: float, strength: float) -> void:
	var slot := patch_cursor
	patch_cursor = (patch_cursor + 1) % PATCH_POOL_SIZE
	var node := patch_nodes[slot]
	var material := patch_materials[slot]

	node.position = position
	node.scale = Vector3(radius * 2.0, radius * 2.0, 1.0)
	node.visible = true
	patch_ages[slot] = 0.0
	patch_lifetimes[slot] = PATH_FROST_LIFE
	patch_active[slot] = 1
	material.set_shader_parameter("effect_age", 0.0)
	material.set_shader_parameter("seed", rng.randf())
	material.set_shader_parameter("intensity", 0.86 * strength)


func _spawn_impact_frost(position: Vector3, radius: float) -> void:
	impact_frost.position = Vector3(position.x, -0.012, position.z)
	impact_frost.scale = Vector3(radius * 2.0, radius * 2.0, 1.0)
	impact_frost.visible = true
	impact_age = 0.0
	impact_active = true
	impact_material.set_shader_parameter("effect_age", 0.0)
	impact_material.set_shader_parameter("seed", rng.randf())
	impact_material.set_shader_parameter("intensity", 1.08)


func _spawn_shockwave(position: Vector3, radius: float) -> void:
	shockwave.position = position + Vector3(0.0, 0.012, 0.0)
	shockwave.scale = Vector3(radius * 2.0, radius * 2.0, 1.0)
	shockwave.visible = true
	shockwave_age = 0.0
	shockwave_active = true
	shockwave_material.set_shader_parameter("effect_age", 0.0)
	shockwave_material.set_shader_parameter("maximum_radius", radius)


func _spawn_frost_burst(position: Vector3) -> void:
	frost_burst.position = position
	frost_burst.visible = true
	burst_age = 0.0
	burst_active = true
	burst_material.set_shader_parameter("effect_age", 0.0)
	burst_material.set_shader_parameter("seed", rng.randf())
	_update_burst_scale(0.0)


func _update_path_patches(delta: float) -> void:
	for i in range(PATCH_POOL_SIZE):
		if patch_active[i] == 0:
			continue
		patch_ages[i] += delta
		var normalized_age := patch_ages[i] / maxf(patch_lifetimes[i], 0.001)
		if normalized_age >= 1.0:
			patch_active[i] = 0
			patch_nodes[i].visible = false
		else:
			patch_materials[i].set_shader_parameter("effect_age", normalized_age)


func _update_impact_frost(delta: float) -> void:
	if not impact_active:
		return
	impact_age += delta
	var normalized_age := impact_age / IMPACT_FROST_LIFE
	if normalized_age >= 1.0:
		impact_active = false
		impact_frost.visible = false
	else:
		impact_material.set_shader_parameter("effect_age", normalized_age)


func _update_shockwave(delta: float) -> void:
	if not shockwave_active:
		return
	shockwave_age += delta
	var normalized_age := shockwave_age / SHOCKWAVE_LIFE
	if normalized_age >= 1.0:
		shockwave_active = false
		shockwave.visible = false
	else:
		shockwave_material.set_shader_parameter("effect_age", normalized_age)


func _update_frost_burst(delta: float) -> void:
	if not burst_active:
		return
	burst_age += delta
	var normalized_age := burst_age / BURST_LIFE
	if normalized_age >= 1.0:
		burst_active = false
		frost_burst.visible = false
	else:
		burst_material.set_shader_parameter("effect_age", normalized_age)
		_update_burst_scale(normalized_age)


func _update_burst_scale(normalized_age: float) -> void:
	var eased := 1.0 - pow(1.0 - clampf(normalized_age, 0.0, 1.0), 5.0)
	var radius := lerpf(1.08, 3.6, eased)
	frost_burst.scale = Vector3(radius, radius * 0.72, radius)
