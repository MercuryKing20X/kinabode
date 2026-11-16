extends "res://tests/test_flower_creation.gd"
# B: 2026-11-11 direction: "伙伴可以拿一朵走到主角面前递过来";
# "仓库有玫瑰才送". The old free cosmetic gift assertions contradicted this.
# Keep the same entry point, now exercising real warehouse/route/save ownership.
func run()->void:
	var w:RefCounted=World.new()
	check(not w.flower_gifts.eligible("codex"),"roadside scenery cannot generate a free gift")
	check(not w.flower_creation.execute("codex",{"intent":"gift_flower","color":"red"}).ok,"empty warehouse rejects gift")
	super.run()
