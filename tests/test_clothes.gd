extends "res://tests/test_base.gd"
## Everything worn shows in every way the game draws a body: each item's
## `draw` names templates that exist; each template draws both on the rig
## (standing, walking, crawling side-on...) and seen from above (TopRig: crawling
## up or down the screen, asleep). The lookbook (tests/lookbook.gd) shows it.


func run() -> void:
	var unknown := []
	var worn := 0
	for id in Items.DEFS:
		var d: Dictionary = Items.DEFS[id]
		if not d.has("slot"):
			continue
		worn += 1
		for p in Clothes.parts(d.get("draw", {})):
			var shape: String = p.get("shape", "")
			if not (Clothes.TEMPLATES.has(shape) or shape in Clothes.BASE_SHAPES):
				unknown.append("%s: %s" % [id, shape])
	check(worn > 20 and unknown.is_empty(), "every garment (%d) is drawn by a template that exists%s" % [worn, "" if unknown.is_empty() else ": " + str(unknown)])

	var no_top := []
	for shape in Clothes.TEMPLATES:
		if not Clothes.TOP_TEMPLATES.has(shape) or Clothes.TOP_TEMPLATES[shape].is_empty():
			no_top.append(shape)
	check(no_top.is_empty(), "every template also draws seen from above%s" % ("" if no_top.is_empty() else ": missing " + str(no_top)))

	# The lookbook's outfits between them wear everything.
	var LB = load("res://tests/lookbook.gd")
	var shown := {}
	for o in LB.OUTFITS:
		for slot in o:
			shown[o[slot]] = true
	var left := []
	for id in Items.DEFS:
		if Items.DEFS[id].has("slot") and not shown.has(id):
			left.append(id)
	check(left.is_empty(), "the lookbook shows every garment%s" % ("" if left.is_empty() else ": not " + str(left)))
