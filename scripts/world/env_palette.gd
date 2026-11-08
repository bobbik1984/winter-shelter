class_name EnvPalette
extends RefCounted

## 环境配色的唯一来源（2026-11-09 用户反馈：庇护所上的枝叶 / 木头太绿、太黄，和周围环境对不上，
## 应该和它们的来源物体同色）。云杉、枯木、倒木、干草在森林 / 资源 / 庇护所里都读这里，不再各写各的颜色。
## 庇护所用的枝条 = 从云杉上砍下来的，所以和云杉同色；柱子 / 横梁 = 枯木同色；垫层干草 = 草丛同色。

## 云杉针叶（很暗的蓝绿；雪盖在上面由 snow_cover 着色器加）。
const SPRUCE := Color(0.035, 0.11, 0.07)
## 立枯木 / 树干（灰褐）。
const DEAD_WOOD := Color(0.30, 0.28, 0.26)
## 倒木 / 湿木（略深的灰褐）。
const LOG := Color(0.27, 0.23, 0.20)
## 干草（偏冷的稻草色；以前三处各写一个更黄的颜色）。
const DRY_GRASS := Color(0.62, 0.52, 0.32)

## 洞内剖面（程序化那几种，顶点色按 sRGB 直接显示、不受光）用的同色相显示值；
## 有 Blender 模型的那几种在 tools/blender/build_shelters.py 的 COLORS 里按同样的色相烘进顶点色。
const SPRUCE_IN := Color(0.11, 0.19, 0.15)
const WOOD_IN := Color(0.35, 0.31, 0.28)
