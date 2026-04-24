extends Node

# Scoring values
const SINGLE_ONE := 100
const SINGLE_FIVE := 50

# Three-of-a-kind base values (index = face value, 0 unused)
const THREE_OF_A_KIND := [0, 1000, 200, 300, 400, 500, 600]

# Four/five/six of a kind multiply the three-of-a-kind value
const FOUR_MULTIPLIER := 2
const FIVE_MULTIPLIER := 3
const SIX_MULTIPLIER := 4

# Combination scores
const STRAIGHT_SCORE := 1500
const THREE_PAIRS_SCORE := 750

# Game rules
const NUM_DICE := 6
const WIN_SCORE := 10000
