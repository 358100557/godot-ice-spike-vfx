extends RefCounted

## CPU procedural crystal builder matching the Three.js Phase 1 geometry.
## The output is non-indexed and every triangle receives one face normal.

const TAU := PI * 2.0
const RING_HEIGHTS := [0.0, 0.22, 0.5, 0.75, 0.92]


static func build_crystal(
	seed: float,
	sides: int = 7,
	taper: float = 0.69,
	roughness: float = 0.09,
	bend: float = 0.66
) -> ArrayMesh:
	var facets: int = maxi(3, sides)
	var tip_radius: float = clampf(taper, 0.01, 0.9)

	var bend_angle: float = _hash11(seed * 1.77) * TAU
	var bend_x: float = cos(bend_angle)
	var bend_z: float = sin(bend_angle)

	var angles: Array[float] = []
	for i in range(facets):
		var jitter: float = (
			(_hash11(seed * 3.13 + float(i) * 7.7) - 0.5)
			* (TAU / float(facets))
			* 0.55
			* roughness
			* 3.0
		)
		angles.append(float(i) / float(facets) * TAU + jitter)

	var rings: Array = []
	for ring_index in range(RING_HEIGHTS.size()):
		var t: float = RING_HEIGHTS[ring_index]
		var base_radius: float = _profile_radius(t, tip_radius) * 0.5
		var drift: float = bend * 0.5 * pow(t, 1.6)
		var y: float = t
		if t > 0.0:
			y += (
				(_hash11(seed * 5.9 + float(ring_index) * 2.3) - 0.5)
				* 0.06
				* roughness
			)

		var ring: Array[Vector3] = []
		for i in range(facets):
			var wobble: float = 1.0 + (
				(_hash11(seed * 11.1 + float(ring_index) * 13.7 + float(i) * 3.9) - 0.5)
				* roughness
				* 1.3
				* (0.35 + 0.65 * t)
			)
			var radius_at_vertex: float = maxf(0.002, base_radius * wobble)
			var angle: float = angles[i]
			ring.append(Vector3(
				cos(angle) * radius_at_vertex + bend_x * drift,
				y,
				sin(angle) * radius_at_vertex + bend_z * drift
			))
		rings.append(ring)

	var apex_drift: float = bend * 0.5
	var apex := Vector3(
		bend_x * apex_drift + (_hash11(seed * 17.3) - 0.5) * 0.09 * roughness,
		1.0,
		bend_z * apex_drift + (_hash11(seed * 19.7) - 0.5) * 0.09 * roughness
	)
	var floor_center := Vector3.ZERO

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()

	for ring_index in range(rings.size() - 1):
		var lower: Array = rings[ring_index]
		var upper: Array = rings[ring_index + 1]
		for i in range(facets):
			var j: int = (i + 1) % facets
			_append_triangle(vertices, normals, lower[i], lower[j], upper[i])
			_append_triangle(vertices, normals, lower[j], upper[j], upper[i])

	var top: Array = rings[rings.size() - 1]
	var base: Array = rings[0]
	for i in range(facets):
		var j: int = (i + 1) % facets
		_append_triangle(vertices, normals, top[i], top[j], apex)
		_append_triangle(vertices, normals, floor_center, base[j], base[i])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _profile_radius(t: float, taper: float) -> float:
	return taper + (1.0 - taper) * pow(1.0 - t, 1.15)


static func _hash11(value: float) -> float:
	var hashed: float = sin(value * 127.1) * 43758.5453123
	return hashed - floor(hashed)


static func _append_triangle(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	a: Vector3,
	b: Vector3,
	c: Vector3
) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)

