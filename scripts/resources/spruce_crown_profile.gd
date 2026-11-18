class_name SpruceCrownProfile
extends Resource
## [TUNE] Candidate art proportions only; not consumed by gameplay/collision/forest placement.
@export var sample_id := "A"
@export_range(4, 9) var tiers := 7
@export_range(12, 24) var radial_segments := 22
@export_range(0.55, 0.8) var valley_radius_ratio := 0.66
@export var lower_tier_y := 0.95
@export var upper_tier_y := 5.75
@export var lower_radius := 1.95
@export var upper_radius := 0.35
@export var lower_bough_height := 1.55
@export var upper_bough_height := 0.95
@export_range(0.0, 0.75) var droop := 0.22
@export_range(0.0, 0.25) var edge_variation := 0.1
@export_range(0.0, 0.2) var tier_variation := 0.06
@export_range(0.0, 0.5) var crown_lean := 0.22

## [TUNE] Common candidate presentation multiplier of EnvPalette.SPRUCE; no separate hardcoded color.
@export_range(1.0, 1.8) var needle_tone_gain := 1.5
