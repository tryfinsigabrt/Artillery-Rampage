## Use Delaunay triangulation as a "confetti" shatter starting point since it creates a higher density mesh
## Then subdivide using centroids of the triangles to create smaller chunks and also combine some of the smaller adjacent triangle chunks together
class_name ShatterDelaunay extends ShatterStrategy

@export_category("Shatter")
@export_range(0, 100) var max_iterations: int = 5

@export_category("Shatter")
@export_range(0, 0.2, 0.01) var min_subdivide_deviation: float = 0.0

@export_category("Shatter")
@export_range(0, 0.3, 0.01) var max_subdivide_deviation: float = 0.15

@export_category("Shatter")
@export_range(0, 100, 0.1) var absolute_min_area: float = 50.0

func shatter(poly: PackedVector2Array, min_area: float, max_area: float) -> Array[PackedVector2Array]:
	if poly.size() < 3:
		return []
	if poly.size() == 3:
		return [poly]

	var points: PackedVector2Array = poly.duplicate()
	var last_point_count:int = 0
	var indices: PackedInt32Array = []

	for i in range(max_iterations):
		last_point_count = points.size()
		indices = Geometry2D.triangulate_delaunay(points)

		# If delaunay fails, then just break or return
		if indices.size() == 0:
			print_debug("body(%s-%s) - shatter: Delaunay triangulation failed" % [name, log_context_node.name])
			if i == 0:
				push_warning("body(%s-%s) - shatter: Delaunay triangulation on original poly failed - returning empty array" % [name, log_context_node.name])
				return []
			# Otherwise we can break if this isn't the first iteration
			break

		# Determine area of the triangles and if they are above the threshold, compute an offseted centroid
		for j in range(0, indices.size(), 3):
			var a: Vector2 = points[indices[j]]
			var b: Vector2 = points[indices[j + 1]]
			var c: Vector2 = points[indices[j + 2]]
			
			# Area of triangle
			var area: float = TerrainUtils.calculate_triangle_area(a, b, c)
			if area <= min_area:
				continue
			
			# Compute centroid to subdivide the triangle further but give it a deviation so that it isn't always the same
			var offset_centroid: Vector2 = _offset_centroid(a, b, c)
			points.append(offset_centroid)
		
		# We are done
		if last_point_count == points.size():
			break

	assert(indices.size() > 0, "body(%s-%s) - shatter: didn't exit out on delaunay failure!" % [name, log_context_node.name])

	# Now that we have points and indices we can combine some adjacent triangles to make the chunks bigger
	var adjacent_indices: Array[PackedInt32Array] = TerrainUtils.get_all_adjacent_polygons(indices)
	var final_points: Array[PackedVector2Array] = []

	var added_points: Dictionary = {}
	var unique_indices: Dictionary = {}

	for i in range(adjacent_indices.size()):
		var triangle_indices: PackedInt32Array = adjacent_indices[i]
		var combined_area: float = 0.0
		var triangle_points: PackedVector2Array = []
		unique_indices.clear()

		for j in range(0, triangle_indices.size(), 3):
			var first_index: int = triangle_indices[j]
			if added_points.has(first_index):
				# Already accounted for the triangle and not just its adjacent neighbor
				if j == 0:
					break
				else:
					continue
			
			var second_index: int = triangle_indices[j + 1]
			var third_index: int = triangle_indices[j + 2]

			var a: Vector2 = points[first_index]
			var b: Vector2 = points[second_index]
			var c: Vector2 = points[third_index]

			var area: float = TerrainUtils.calculate_triangle_area(a, b, c)
			combined_area += area

			# Optimized case to not check the dictionary first time through
			if j == 0:
				triangle_points.append(a)
				triangle_points.append(b)
				triangle_points.append(c)

				unique_indices[first_index] = true
				unique_indices[second_index] = true
				unique_indices[third_index] = true

			elif combined_area < max_area:
				# Make sure we don't duplicate the points on the adjacent indices
				if first_index not in unique_indices:
					unique_indices[first_index] = true
					triangle_points.append(a)
				if second_index not in unique_indices:
					unique_indices[second_index] = true
					triangle_points.append(b)
				if third_index not in unique_indices:
					unique_indices[third_index] = true
			else:
				break

			added_points[first_index] = true
		
		if not triangle_points.is_empty():
			final_points.append(triangle_points)

	# Now we have the points and just need to turn them into polygons
	var poly_points_list: Array[PackedVector2Array] = [] 
	for i in range(final_points.size()):
		var poly_points: PackedVector2Array = _points_to_poly(final_points[i])
		# Make sure polygon isn't below threshold size
		if not poly_points.is_empty() and TerrainUtils.calculate_polygon_area(poly_points) >= absolute_min_area:
			poly_points_list.append(poly_points)

	return poly_points_list

# Offset the centroid of the triangle formed by p1, p2, and p3 so that the fracture isn't always predictable
# Do calculations in barycentric coordinates for efficiency and to stay within triangle
func _offset_centroid(p1: Vector2, p2: Vector2, p3: Vector2) -> Vector2:
	# Centroid in barycentric coordinates
	var w1:float = 1 / 3.0
	var w2:float = w1
	var w3:float = w1

	# Apply small random offsets to the barycentric weights
	var offset1 := MathUtils.randf_range_signed(min_subdivide_deviation, max_subdivide_deviation)
	var offset2 := MathUtils.randf_range_signed(min_subdivide_deviation, max_subdivide_deviation)
	var offset3 := -offset1 - offset2  # Ensure weights sum to 1
	
	w1 += offset1
	w2 += offset2
	w3 += offset3

	# Normalize to ensure weights sum to 1
	var total := w1 + w2 + w3
	w1 /= total
	w2 /= total
	w3 /= total

	var min_weight: float = 1 / 3.0 - max_subdivide_deviation

	# Apply redistribution logic for weights below min_weight
	if w1 < min_weight:
		var deficit := min_weight - w1  # How much needs to be added
		var sum_other := w2 + w3
		if sum_other > 0.0:  # Redistribute only if the denominator is valid
			w2 -= deficit * (w2 / sum_other)
			w3 -= deficit * (w3 / sum_other)
		w1 = min_weight
	if w2 < min_weight:
		var deficit := min_weight - w2
		var sum_other := w1 + w3
		if sum_other > 0.0:
			w1 -= deficit * (w1 / sum_other)
			w3 -= deficit * (w3 / sum_other)
		w2 = min_weight
	if w3 < min_weight:
		var deficit := min_weight - w3
		var sum_other := w1 + w2
		if sum_other > 0.0:
			w1 -= deficit * (w1 / sum_other)
			w2 -= deficit * (w2 / sum_other)
		w3 = min_weight

	# Check to make sure still inside triangle and fallback to centroid if not
	if not TerrainUtils.is_inside_triange_barycentric(w1, w2, w3):
		print_debug("body(%s-%s) - shatter: barycentric weights out of bounds: w1=%f;w2=%f;w3=%f - using centroid" % [name, log_context_node.name, w1, w2, w3])
		w1 = 1 / 3.0
		w2 = w1
		w3 = w1

	# Convert barycentric coordinates to Cartesian coordinates
	return TerrainUtils.barycentric_to_cartesian(w1, w2, w3, p1, p2, p3)
