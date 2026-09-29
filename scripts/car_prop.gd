class_name CarProp
extends Node2D
## A car standing where it was left (a car made after the city was built:
## Vehicles.vehicle_add). While someone drives it, the driver draws it.

var v: Dictionary


func _draw() -> void:
	CarArt.draw(self, v.dir, CarArt.spec_of(v))
