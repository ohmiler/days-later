Zones drawn by hand, one file each (listed in data/zones.cfg with plan=).
Draw them after the real place (OpenStreetMap is a good guide: credit it),
squeezed to fit (a zone is a few hundred cells; a cell is about a metre),
turned so the main streets run straight across or up and down.

Everything goes in a [plan] section. x runs east, y south, in cells.

  size       [width, height]
  spawn      [x, y] where new survivors start (on a pavement, not in a building)
  roads      [{"rect": [x, y, w, h], "name": "...", "median": true}, ...]
             A street along its longer side. Pavements (two cells) are added
             either side. median: a raised island down the middle (wide streets).
  junctions  [[x, y, w, h], ...] where streets meet (zebra crossings are painted)
  circle     {"at": [x, y], "r": 28, "island": 12}: a roundabout: the road's
             outer radius, the island's (garden, with the monument in the middle)
  canals     [{"y": 16, "h": 6, "name": "..."}]: a canal right across, with
             towpaths; streets crossing it become bridges
  bts        {"x": 200, "around": 36, "station": [196, 214]}: the skytrain up
             column x, round the far side of the roundabout at that radius,
             a station over those rows
  blocks     [{"rect": [x, y, w, h], "use": "...", "name": "..."}]: the land
             between the streets, run right up to the pavements. For now every
             block is shophouses and sois (use says what it will become:
             hospital, military_hospital, mall, office, market, shophouses);
             shophouses that would stand on the roundabout are left out
  exits      [{"id", "edge", "rect": [x, y, w, h], "to", "to_exit"}]: ways out,
             where a street meets the map's edge; to: the zone it leads to
             (one marked todo in zones.cfg: a sign, no way through yet)

The bottom three rows are pavement (shop fronts face south, onto it).
Changing a plan changes the city: bump CityGen.GEN (saves move to a new
city) and update the fingerprint in tests/test_city.gd.
