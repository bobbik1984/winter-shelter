class_name ShelterPreset
extends Resource

enum ShelterType {
	SNOW_TRENCH,
	BASIC_CAVE,
	RAISED_CAVE
}

@export var type: ShelterType = ShelterType.RAISED_CAVE
@export var name: String = "Raised Snow Cave"
@export var min_snow_depth: float = 2.0
@export var build_time_minutes: int = 120
@export var has_cold_sink: bool = true
@export var base_insulation_bonus: float = 18.0
