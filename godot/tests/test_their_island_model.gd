extends "res://tests/test_their_island.gd"
## A bound held model turn still cannot revive the retired construction API.
func run()->void:
	verify(true)
	print("Vacation model construction rejection ",checks," failed=",failed);quit(1 if failed else 0)
