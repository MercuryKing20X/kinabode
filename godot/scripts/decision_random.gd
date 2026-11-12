extends RefCounted
## Decisions have independent state. Mirror their original public RNG draws so
## authored speech and explicit public seed controls retain the legacy contract.
var authored:RandomNumberGenerator
var independent:=RandomNumberGenerator.new()
var seen_seed:=0
var seeded:=false
var state:int:
	get:
		sync_seed();return independent.state
func _init(source:RandomNumberGenerator)->void:authored=source
func sync_seed()->void:
	if not seeded or seen_seed!=authored.seed:
		seen_seed=authored.seed;independent.seed=seen_seed;seeded=true
func randf()->float:
	sync_seed();authored.randf();return independent.randf()
func randf_range(low:float,high:float)->float:
	sync_seed();authored.randf_range(low,high);return independent.randf_range(low,high)
func randi()->int:
	sync_seed();authored.randi();return independent.randi()
func randi_range(low:int,high:int)->int:
	sync_seed();authored.randi_range(low,high);return independent.randi_range(low,high)
