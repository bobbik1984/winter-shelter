class_name EnvironmentDetailSettings
extends Resource
## [TUNE] Art/presentation budget only. Never changes collision, snow depth, resources or shelter scores.
@export var enabled := true
@export_range(0, 6) var rock_chips_per_group := 3
@export_range(1, 12) var tree_base_stride := 4
@export_range(8.0, 80.0) var view_distance_m := 38.0
@export_range(5.0, 40.0) var chunk_size_m := 25.0
@export_range(0.0, 50.0) var max_slope_deg := 32.0
@export var snow_color := Color(0.83, 0.89, 0.96)
@export var rock_color := Color(0.27, 0.29, 0.33)
@export var compacted_snow_color := Color(0.53, 0.63, 0.77)
@export var footprint_rim_color := Color(0.86, 0.92, 0.98)
@export_range(0.0, 0.3) var surface_detail_strength := 0.12
@export_range(0, 16) var worksite_prints := 10

## [TUNE] Neutral sky fill keeps shaded detail readable. Sun direction/time stay authoritative.
@export var ambient_fill_color := Color(0.72, 0.78, 0.85)
@export var ambient_day_energy := 0.8
@export var ambient_night_energy := 0.22

## [TUNE] Existing entrance lamp: a soft interior cue, not an emissive door or a heating fire.
@export var entrance_day_energy := 0.12
@export var entrance_night_energy := 0.75
