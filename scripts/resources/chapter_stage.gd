class_name ChapterStage
extends Resource

## [GAME] 主线小关的独立课题；与章节共用装备和环境规则。
@export_multiline var lesson: String = ""
@export var introduced_presets: PackedStringArray = PackedStringArray()
@export var target_presets: PackedStringArray = PackedStringArray()
## [TUNE] 覆盖主线小关的开局时刻和难度；-1 时沿用章节插值。
@export var start_minutes: int = -1
@export_range(0.0, 1.0) var difficulty: float = 0.0
