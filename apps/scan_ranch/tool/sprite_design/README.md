# Sprite design workbench (Python + Pillow)

Work in progress: monster sprites awaiting the owner's approval.

- `hd.py` — 64×64 renderer: hand-placed shapes (ellipses, tapered tubes,
  polygons) grouped into parts, shaded with a distance-field "volume" model
  (5-tone hue-shifted ramps), inner lines between parts, coloured outline.
- `hd_drake.py`, `hd_hound.py` — first two 64×64 silhouettes.
- `hd_more.py`, `hd_fix.py` — the other eight silhouettes.
- `hd_all.py` — all ten with the approved CRT look: `PYTHONPATH=. python3 hd_all.py`.
- `scan.py` — scan-line / CRT effect (option 4 approved: monsters only, always on).
- `kit.py`, `d2.py`–`d4.py` — earlier 32×32 hand-pixelled drafts (10 silhouettes).

Once approved, the renderer and shape data get ported to Dart so creatures are
generated on the phone.
