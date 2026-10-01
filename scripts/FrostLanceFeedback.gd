class_name FrostLanceFeedback
extends Node

## Phase 5-only atmosphere and feedback layer. It consumes the existing cast
## state read-only and never changes crystal, particle, or Ground FX settings.

const LIGHT_COLOR := Color("7fd4ff")
const LIGHT_BASE_ENERGY := 2.8
const LIGHT_IMPACT_MULTIPLIER := 1.6
const LIGHT_HOLD_END_ENERGY := 0.35
const LIGHT_RANGE := 13.0
const LIGHT_TRAVEL_HEIGHT := 1.15
const LIGHT_IMPACT_HEIGHT := 1.8
const LIGHT_BOOST_TIME := 0.24

const FLASH_COLOR := Color("eafaff")
const FLASH_PEAK_ALPHA := 0.13
const FLASH_DURATION := 0.18

const RUMBLE_POSITION_AMPLITUDE := 0.008
const RUMBLE_ROTATION_AMPLITUDE := 0.00045
const RUMBLE_FREQUENCY := 19.0
const IMPACT_SHAKE_DURATION := 0.9
const IMPACT_POSITION_AMPLITUDE := 0.13
const IMPACT_ROTATION_AMPLITUDE := 0.006
const IMPACT_FREQUENCY := 26.0
const BLOOM_SHADER: Shader = preload("res://shaders/frost_lance_bloom.gdshader")

@onready var dynamic_light: OmniLight3D = $DynamicLight
@onready var camera_rig: Node3D = $"../../CameraRig"
@onready var bloom_overlay: ColorRect = $"../../FeedbackCanvas/BloomOverlay"
@onready var screen_flash: ColorRect = $"../../FeedbackCanvas/ScreenFlash"

var camera_rig_rest := Transform3D.IDENTITY
var travelling := false
var rumble_time := 0.0
var impact_elapsed := IMPACT_SHAKE_DURATION
var impact_shake_active := false
var flash_elapsed := FLASH_DURATION
var flash_active := false
var auto_test := false
var captured_impact := false


func _ready() -> void:
	camera_rig_rest = camera_rig.transform
	auto_test = "--auto-test" in OS.get_cmdline_user_args()
	dynamic_light.light_color = LIGHT_COLOR
	dynamic_light.light_energy = 0.0
	dynamic_light.omni_range = LIGHT_RANGE
	dynamic_light.omni_attenuation = 1.65
	dynamic_light.light_specular = 0.65
	dynamic_light.shadow_enabled = false
	dynamic_light.visible = false
	var bloom_material := ShaderMaterial.new()
	bloom_material.shader = BLOOM_SHADER
	bloom_material.set_shader_parameter("threshold", 0.82)
	bloom_material.set_shader_parameter("intensity", 0.16)
	bloom_overlay.material = bloom_material
	_set_flash_alpha(0.0)


func _process(delta: float) -> void:
	_update_flash(delta)
	_update_camera_feedback(delta)


func configure_environment(environment: Environment) -> void:
	# Compatibility's native Glow changes the whole-frame composite even at low
	# values. Keep it disabled and use the selective high-pass overlay instead.
	environment.glow_enabled = false


func begin_cast() -> void:
	travelling = true
	rumble_time = 0.0
	impact_elapsed = IMPACT_SHAKE_DURATION
	impact_shake_active = false
	flash_elapsed = FLASH_DURATION
	flash_active = false
	camera_rig.transform = camera_rig_rest
	_set_flash_alpha(0.0)
	dynamic_light.visible = true
	dynamic_light.light_energy = LIGHT_BASE_ENERGY


func update_travel(front_position: Vector3) -> void:
	travelling = true
	dynamic_light.visible = true
	dynamic_light.position = front_position + Vector3.UP * LIGHT_TRAVEL_HEIGHT
	dynamic_light.light_energy = LIGHT_BASE_ENERGY


func emit_impact(impact_position: Vector3) -> void:
	travelling = false
	dynamic_light.visible = true
	dynamic_light.position = impact_position + Vector3.UP * LIGHT_IMPACT_HEIGHT
	dynamic_light.light_energy = LIGHT_BASE_ENERGY * LIGHT_IMPACT_MULTIPLIER
	impact_elapsed = 0.0
	impact_shake_active = true
	flash_elapsed = 0.0
	flash_active = true
	_set_flash_alpha(FLASH_PEAK_ALPHA)
	if auto_test and not captured_impact:
		captured_impact = true
		call_deferred("_capture_impact_preview")


func update_hold(hold_progress: float) -> void:
	var normalized_hold := clampf(hold_progress, 0.0, 1.0)
	if impact_elapsed < LIGHT_BOOST_TIME:
		var boost_fade := smoothstep(0.0, LIGHT_BOOST_TIME, impact_elapsed)
		dynamic_light.light_energy = lerpf(
			LIGHT_BASE_ENERGY * LIGHT_IMPACT_MULTIPLIER,
			LIGHT_BASE_ENERGY * 1.05,
			boost_fade
		)
	else:
		dynamic_light.light_energy = lerpf(
			LIGHT_BASE_ENERGY * 1.05,
			LIGHT_HOLD_END_ENERGY,
			smoothstep(0.0, 1.0, normalized_hold)
		)


func update_fade(fade_progress: float) -> void:
	travelling = false
	var normalized_fade := clampf(fade_progress, 0.0, 1.0)
	dynamic_light.light_energy = lerpf(
		LIGHT_HOLD_END_ENERGY,
		0.0,
		smoothstep(0.0, 1.0, normalized_fade)
	)
	if normalized_fade >= 1.0:
		dynamic_light.visible = false


func finish_cast() -> void:
	travelling = false
	impact_shake_active = false
	flash_active = false
	dynamic_light.light_energy = 0.0
	dynamic_light.visible = false
	_set_flash_alpha(0.0)
	camera_rig.transform = camera_rig_rest


func _update_flash(delta: float) -> void:
	if not flash_active:
		return
	flash_elapsed += delta
	var normalized_age := flash_elapsed / FLASH_DURATION
	if normalized_age >= 1.0:
		flash_active = false
		_set_flash_alpha(0.0)
		return
	var fade := pow(1.0 - normalized_age, 3.0)
	_set_flash_alpha(FLASH_PEAK_ALPHA * fade)


func _update_camera_feedback(delta: float) -> void:
	var position_offset := Vector3.ZERO
	var rotation_offset := Vector3.ZERO

	if travelling:
		rumble_time += delta
		position_offset += Vector3(
			sin(rumble_time * RUMBLE_FREQUENCY * 1.17),
			sin(rumble_time * RUMBLE_FREQUENCY * 1.71 + 1.2),
			0.0
		) * RUMBLE_POSITION_AMPLITUDE
		rotation_offset += Vector3(
			sin(rumble_time * RUMBLE_FREQUENCY * 1.31 + 0.7),
			sin(rumble_time * RUMBLE_FREQUENCY * 0.93),
			0.0
		) * RUMBLE_ROTATION_AMPLITUDE

	if impact_shake_active:
		impact_elapsed += delta
		var normalized_age := clampf(impact_elapsed / IMPACT_SHAKE_DURATION, 0.0, 1.0)
		var envelope := pow(1.0 - normalized_age, 2.2)
		var phase := impact_elapsed * IMPACT_FREQUENCY
		position_offset += Vector3(
			sin(phase * 1.23),
			sin(phase * 1.67 + 0.9),
			sin(phase * 0.81 + 2.1) * 0.35
		) * IMPACT_POSITION_AMPLITUDE * envelope
		rotation_offset += Vector3(
			sin(phase * 1.41 + 0.4),
			sin(phase * 1.09 + 1.7),
			sin(phase * 1.83) * 0.35
		) * IMPACT_ROTATION_AMPLITUDE * envelope
		if normalized_age >= 1.0:
			impact_shake_active = false

	if not travelling and not impact_shake_active:
		camera_rig.transform = camera_rig_rest
		return

	var feedback_transform := Transform3D(Basis.from_euler(rotation_offset), position_offset)
	camera_rig.transform = camera_rig_rest * feedback_transform


func _set_flash_alpha(alpha: float) -> void:
	screen_flash.color = Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, alpha)


func _capture_impact_preview() -> void:
	await get_tree().create_timer(0.04).timeout
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.qa"))
	var output_path := ProjectSettings.globalize_path("res://.qa/phase5_impact.png")
	var error := image.save_png(output_path)
	print("PHASE5_QA_CAPTURE: %s error=%d" % [output_path, error])
