class_name IceCrystalShaderController
extends Resource

## Phase 2-only material settings and ShaderMaterial construction.
## Geometry, distribution, transforms, and animation remain owned by the experiment.

const ICE_CRYSTAL_SHADER: Shader = preload("res://shaders/ice_crystal.gdshader")

@export_group("Palette")
@export var color_ice := Color("8adaff")
@export var color_deep := Color("3e737a")
@export var color_rim := Color("f2feff")
@export var color_core := Color("638797")

@export_group("Surface")
@export_range(0.0, 5.0, 0.01) var fresnel_strength := 2.3
@export_range(0.1, 8.0, 0.05) var fresnel_power := 2.4
@export_range(0.0, 2.0, 0.01) var fracture_strength := 0.62
@export_range(0.1, 24.0, 0.1) var fracture_scale := 6.5
@export_range(0.0, 2.0, 0.01) var veins_strength := 0.45
@export_range(0.1, 16.0, 0.1) var veins_scale := 3.2
@export_range(0.0, 2.0, 0.01) var frost_line_strength := 0.5
@export_range(0.0, 4.0, 0.01) var glow_strength := 0.85
@export_range(0.0, 6.0, 0.01) var birth_glow_strength := 1.6
@export_range(0.0, 1.0, 0.01) var opacity := 0.92

@export_group("Glint")
@export_range(0.0, 4.0, 0.01) var glint_strength := 1.1
@export_range(1.0, 80.0, 0.5) var glint_scale := 34.0
@export_range(0.0, 4.0, 0.01) var glint_speed := 0.7

@export_group("Birth")
@export_range(0.05, 2.0, 0.01) var birth_fade := 0.45


func create_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = ICE_CRYSTAL_SHADER
	apply_to(material)
	return material


func apply_to(material: ShaderMaterial) -> void:
	material.set_shader_parameter("color_ice", color_ice)
	material.set_shader_parameter("color_deep", color_deep)
	material.set_shader_parameter("color_rim", color_rim)
	material.set_shader_parameter("color_core", color_core)
	material.set_shader_parameter("fresnel_strength", fresnel_strength)
	material.set_shader_parameter("fresnel_power", fresnel_power)
	material.set_shader_parameter("fracture_strength", fracture_strength)
	material.set_shader_parameter("fracture_scale", fracture_scale)
	material.set_shader_parameter("veins_strength", veins_strength)
	material.set_shader_parameter("veins_scale", veins_scale)
	material.set_shader_parameter("frost_line_strength", frost_line_strength)
	material.set_shader_parameter("glow_strength", glow_strength)
	material.set_shader_parameter("birth_glow_strength", birth_glow_strength)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("glint_strength", glint_strength)
	material.set_shader_parameter("glint_scale", glint_scale)
	material.set_shader_parameter("glint_speed", glint_speed)
