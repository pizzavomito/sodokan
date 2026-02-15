extends Node2D

var teleporter_id : int = 0
var linked_teleporter_id : int = 0

func initialize(tp_id: int, linked_id: int):
	teleporter_id = tp_id
	linked_teleporter_id = linked_id
