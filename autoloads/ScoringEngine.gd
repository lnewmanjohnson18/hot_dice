extends Node

# Returns the best score for a set of die values, or 0 if unscoreable.
# values: Array[int] of face values (1-6)
func score(values: Array) -> int:
	if values.is_empty():
		return 0

	var counts := _count(values)

	# Straight: one of each 1-6
	if values.size() == 6 and _is_straight(counts):
		return GameConfig.STRAIGHT_SCORE

	# Three pairs
	if values.size() == 6 and _is_three_pairs(counts):
		return GameConfig.THREE_PAIRS_SCORE

	var total := 0
	for face in range(1, 7):
		var n: int = counts[face]
		if n == 0:
			continue
		if n >= 3:
			var base: int = GameConfig.THREE_OF_A_KIND[face]
			var multiplier := 1
			if n == 4:
				multiplier = GameConfig.FOUR_MULTIPLIER
			elif n == 5:
				multiplier = GameConfig.FIVE_MULTIPLIER
			elif n == 6:
				multiplier = GameConfig.SIX_MULTIPLIER
			total += base * multiplier
		else:
			if face == 1:
				total += n * GameConfig.SINGLE_ONE
			elif face == 5:
				total += n * GameConfig.SINGLE_FIVE
	return total

# Returns true if the given subset of values contributes any score.
func is_scoreable(values: Array) -> bool:
	return score(values) > 0

# Returns true if at least one scoreable subset exists in the roll.
func has_any_score(values: Array) -> bool:
	for face in range(1, 7):
		if face == 1 or face == 5:
			if values.has(face):
				return true
	var counts := _count(values)
	for face in range(1, 7):
		if counts[face] >= 3:
			return true
	if values.size() == 6 and (_is_straight(counts) or _is_three_pairs(counts)):
		return true
	return false

func _count(values: Array) -> Array:
	var counts := [0, 0, 0, 0, 0, 0, 0]
	for v in values:
		counts[v] += 1
	return counts

func _is_straight(counts: Array) -> bool:
	for face in range(1, 7):
		if counts[face] != 1:
			return false
	return true

func _is_three_pairs(counts: Array) -> bool:
	var pairs := 0
	for face in range(1, 7):
		if counts[face] == 2:
			pairs += 1
	return pairs == 3
