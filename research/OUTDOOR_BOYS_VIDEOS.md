# Outdoor Boys 冬季视频清单（用户推荐，2026-11-01）

> 用途：为庇护所目录（CORE_GAMEPLAY §9.3）、过夜机制（D14 讨论中）提供 `[REAL]` 参考。
> 链接由 Claude 用 youtube.com 限定搜索找到；✅ = 标题完全匹配，⚠️ = 只找到近似 / 短视频，需要用户确认。
> 获取方式：NotebookLM 直接添加 YouTube 链接作为来源（它读字幕，不受 yt-dlp 反爬影响），用下方提示词生成逐视频卡片，结果存到 `references/` 后交给 Claude 整理进本目录。

| # | 标题 | 链接 | 状态 |
| :-- | :--- | :--- | :-- |
| 1 | 3 Days in Arctic Survival Shelter - Solo Bushcraft Camping & Blacksmithing | https://www.youtube.com/watch?v=iys_pmJSp9M | ✅ |
| 2 | 3 Days in Arctic with Bushcraft Hot Tent & No Sleeping Bag | https://www.youtube.com/watch?v=4PDLO-iC3FM | ✅ |
| 3 | 3 Days Stranded in Alaska Without a Tent - Camping in Deep Snow Survival Shelters | 未找到；近似：https://www.youtube.com/watch?v=S_c45EOojTM（"Deep Snow Survival Camping in Alaska - Building a Winter Survival Shelter"） | ⚠️ |
| 4 | Camping in Alaska's Deepest Snow with a Dugout Survival Shelter | https://www.youtube.com/watch?v=ggWZoH9PeIU | ✅ |
| 5 | Camping Under the Snow in Hot Tent - Heated Snow Shelter & Sledding Hill of Death | https://www.youtube.com/watch?v=A6v5Vj6h_fQ | ✅ |
| 6 | Camping Under the Snow in Survival Shelter | https://www.youtube.com/watch?v=PTnrqkMpfj8 | ✅ |
| 7 | Can I Survive Alaskan Winter with No Sleeping Bag, No Tent & No Tarp? | https://www.youtube.com/watch?v=qRODjitiKP8 | ✅ |
| 8 | HOT ROCKS in my Bushcraft Cot - Winter Camping in Alaska with a Survival Shelter | 只找到 Shorts：https://www.youtube.com/shorts/dPLmochMWnc（完整版待确认） | ⚠️ |
| 9 | Lost in Alaska - How to NOT Freeze to Death! Winter Survival Camping & Bushcraft (No Tent or Bag) | https://www.youtube.com/watch?v=sqoOzGMqCQU | ✅ |
| 10 | Survival Camping 9ft/3m Under Snow - Giant Winter Bushcraft Shelter and Quinzee | https://www.youtube.com/watch?v=rPAhFD8hKxQ | ✅ |
| 11 | Winter Camping in Snow Storm with Survival Shelter & Bushcraft Cot | https://www.youtube.com/watch?v=oNxUsPCUWvU | ✅ |

## NotebookLM 提示词（逐视频卡片，复制使用）

```text
For EACH video source separately, write a card with exactly these headings. Use only what is said or shown in that video; write "not stated" if unknown. Quote numbers exactly as given (temperatures, depths, times, wind).

1. Title
2. Conditions: air temperature (day / night), wind, snow depth and snow type (powder, crust, wind-packed), terrain (slope, forest density, lake, cliff, open ground)
3. Gear brought (and what was deliberately left behind: tent, sleeping bag, tarp, shovel, saw, axe, stove)
4. Shelter built: type, which natural feature it used (fallen tree, root wad, big spruce, snow drift, slope), materials, build steps
5. Build time and effort (how long, how tired / sweaty / wet he got)
6. Fire: where relative to the shelter, fuel type and amount, how long it burned, whether it was kept going at night
7. The night, hour by hour if possible: when he went to sleep, every time he woke up and why (cold, fire died, snow, condensation), what he did each time (added wood, hot rocks, ate, drank, moved), how warm or cold he felt by morning
8. Problems and mistakes: what went wrong, what he would do differently
9. Survival tips he states explicitly (quote them)
10. Anything surprising or counter-intuitive
```

第 7 项（夜里每次醒来的原因与对策）直接服务于"可玩的夜晚"设计（夜间快进 + 冷醒后添柴 / 清通风口等）。
