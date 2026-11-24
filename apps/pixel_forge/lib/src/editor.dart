import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pixel_kit/pixel_kit.dart';

enum Tool {
  pencil('Pencil', 'B'),
  eraser('Eraser', 'E'),
  line('Line', 'L'),
  rect('Rectangle', 'U'),
  ellipse('Ellipse', 'O'),
  fill('Fill', 'G'),
  picker('Pick colour', 'I'),
  select('Select', 'M');

  const Tool(this.label, this.key);
  final String label;
  final String key;
}

sealed class _Undo {}

/// Pixels of one cel before and after a change.
class _CelUndo extends _Undo {
  _CelUndo(this.frame, this.layer, this.before, this.after);
  final int frame, layer;
  final Uint32List before, after;
}

/// The whole sprite before and after (layer/frame/size changes).
class _SpriteUndo extends _Undo {
  _SpriteUndo(this.before, this.after, this.layer);
  final Sprite before, after;
  final int layer;
}

class Editor extends ChangeNotifier {
  Editor({Sprite? sprite}) : sprite = sprite ?? Sprite.blank(32, 32);

  Sprite sprite;
  String name = 'Untitled';
  int frame = 0;
  int layer = 0;
  Tool tool = Tool.pencil;
  int brushSize = 1;
  bool mirrorX = false, mirrorY = false;
  bool shapeFilled = false;
  bool fillGlobal = false;
  int primary = 0xFF000000;
  int secondary = 0xFFFFFFFF;
  Palette palette = builtInPalettes[2];

  /// Bumped on every pixel change (the canvas redraws).
  int version = 0;

  /// Selection (in sprite pixels) and whether its pixels are lifted.
  Rect? selection;
  PixelPatch? _floating;
  Rect? _floatOrigin;
  PixelPatch? clipboard;

  final _undo = <_Undo>[];
  final _redo = <_Undo>[];
  static const _maxUndo = 60;

  // Stroke state.
  Uint32List? _before;
  int _sx = 0, _sy = 0, _lx = 0, _ly = 0;
  bool _stroking = false;
  bool _movingSelection = false;
  bool dirty = false;

  Uint32List get cel => sprite.cel(frame, layer);
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void _changed() {
    version++;
    dirty = true;
    notifyListeners();
  }

  // ---- Undo ----

  void _push(_Undo u) {
    _undo.add(u);
    if (_undo.length > _maxUndo) _undo.removeAt(0);
    _redo.clear();
  }

  /// Records a structural change: call [change] and keep the old sprite.
  void _structural(void Function() change) {
    commitFloating();
    final before = sprite.copy();
    change();
    _push(_SpriteUndo(before, sprite.copy(), layer));
    _clampIndexes();
    _changed();
  }

  void undo() {
    commitFloating();
    if (_undo.isEmpty) return;
    final u = _undo.removeLast();
    switch (u) {
      case _CelUndo():
        sprite.cel(u.frame, u.layer).setAll(0, u.before);
      case _SpriteUndo():
        sprite = u.before.copy();
        layer = u.layer;
    }
    _redo.add(u);
    _clampIndexes();
    _changed();
  }

  void redo() {
    if (_redo.isEmpty) return;
    final u = _redo.removeLast();
    switch (u) {
      case _CelUndo():
        sprite.cel(u.frame, u.layer).setAll(0, u.after);
      case _SpriteUndo():
        sprite = u.after.copy();
    }
    _undo.add(u);
    _clampIndexes();
    _changed();
  }

  void _clampIndexes() {
    frame = frame.clamp(0, sprite.frames.length - 1);
    layer = layer.clamp(0, sprite.layers.length - 1);
    final s = selection;
    if (s != null) {
      final c = s.clampTo(sprite.width, sprite.height);
      selection = c.isEmpty ? null : c;
    }
  }

  // ---- Settings ----

  void setTool(Tool t) {
    if (t != Tool.select) commitFloating();
    tool = t;
    notifyListeners();
  }

  void setBrush(int s) {
    brushSize = s.clamp(1, 8);
    notifyListeners();
  }

  void setPrimary(int c) {
    primary = c;
    notifyListeners();
  }

  void swapColors() {
    final t = primary;
    primary = secondary;
    secondary = t;
    notifyListeners();
  }

  void toggleMirrorX() {
    mirrorX = !mirrorX;
    notifyListeners();
  }

  void toggleMirrorY() {
    mirrorY = !mirrorY;
    notifyListeners();
  }

  void toggleFilled() {
    shapeFilled = !shapeFilled;
    notifyListeners();
  }

  void setFillGlobal(bool v) {
    fillGlobal = v;
    notifyListeners();
  }

  void setPalette(Palette p) {
    palette = p;
    notifyListeners();
  }

  // ---- Strokes (x, y in sprite pixels; may be outside) ----

  Canvas _canvas() => Canvas(
    cel,
    sprite.width,
    sprite.height,
    mirrorX: mirrorX,
    mirrorY: mirrorY,
    mask: _floating == null ? selection : null,
  );

  int get _ink => tool == Tool.eraser ? 0 : primary;

  void strokeStart(int x, int y, {bool alt = false}) {
    if (tool == Tool.picker) {
      if (sprite.inside(x, y)) {
        final c = sprite.flatten(frame)[y * sprite.width + x];
        if (c != 0) setPrimary(c);
      }
      return;
    }
    if (tool == Tool.select) {
      _selectStart(x, y);
      return;
    }
    if (!sprite.layers[layer].visible) return;
    _before = Uint32List.fromList(cel);
    _stroking = true;
    _sx = _lx = x;
    _sy = _ly = y;
    final c = _canvas();
    switch (tool) {
      case Tool.pencil:
      case Tool.eraser:
        c.brush(x, y, _ink, size: brushSize);
      case Tool.fill:
        c.fill(x, y, primary, global: fillGlobal);
      default:
        _drawShape(x, y);
    }
    _changed();
  }

  void strokeMove(int x, int y) {
    if (tool == Tool.select) {
      _selectMove(x, y);
      return;
    }
    if (!_stroking) return;
    switch (tool) {
      case Tool.pencil:
      case Tool.eraser:
        if (x == _lx && y == _ly) return;
        _canvas().line(_lx, _ly, x, y, _ink, size: brushSize);
      case Tool.line:
      case Tool.rect:
      case Tool.ellipse:
        _drawShape(x, y);
      default:
        return;
    }
    _lx = x;
    _ly = y;
    _changed();
  }

  void _drawShape(int x, int y) {
    cel.setAll(0, _before!);
    final c = _canvas();
    switch (tool) {
      case Tool.line:
        c.line(_sx, _sy, x, y, primary, size: brushSize);
      case Tool.rect:
        c.rect(_sx, _sy, x, y, primary, filled: shapeFilled);
      case Tool.ellipse:
        c.ellipse(_sx, _sy, x, y, primary, filled: shapeFilled);
      default:
        break;
    }
  }

  void strokeEnd() {
    if (tool == Tool.select) {
      _movingSelection = false;
      return;
    }
    if (!_stroking) return;
    _stroking = false;
    final before = _before!;
    _before = null;
    if (!listEquals(before, cel)) {
      _push(_CelUndo(frame, layer, before, Uint32List.fromList(cel)));
    }
  }

  /// A second finger arrived: undo the stroke in progress.
  void strokeCancel() {
    if (_stroking && _before != null) {
      cel.setAll(0, _before!);
      _changed();
    }
    _stroking = false;
    _before = null;
    _movingSelection = false;
  }

  // ---- Selection ----

  void _selectStart(int x, int y) {
    final s = selection;
    if (s != null && s.contains(x, y)) {
      // Drag inside: lift the pixels and move them.
      if (_floating == null) {
        _before = Uint32List.fromList(cel);
        _floating = PixelPatch.copy(cel, sprite.width, s);
        _floatOrigin = s;
        clearRect(cel, sprite.width, s);
      }
      _movingSelection = true;
      _sx = x;
      _sy = y;
      return;
    }
    commitFloating();
    _movingSelection = false;
    _sx = x.clamp(0, sprite.width - 1);
    _sy = y.clamp(0, sprite.height - 1);
    selection = Rect.fromPoints(_sx, _sy, _sx, _sy);
    notifyListeners();
  }

  void _selectMove(int x, int y) {
    final s = selection;
    if (s == null) return;
    if (_movingSelection && _floating != null) {
      final dx = x - _sx, dy = y - _sy;
      if (dx == 0 && dy == 0) return;
      _sx = x;
      _sy = y;
      _setFloatingAt(s.shift(dx, dy));
      return;
    }
    if (_movingSelection) return;
    final cx = x.clamp(0, sprite.width - 1), cy = y.clamp(0, sprite.height - 1);
    selection = Rect.fromPoints(_sx, _sy, cx, cy);
    notifyListeners();
  }

  void _setFloatingAt(Rect r) {
    final f = _floating!;
    // Redraw: the cel without the lifted pixels, then the patch.
    final base = Uint32List.fromList(_before!);
    clearRect(base, sprite.width, _floatOrigin!);
    cel.setAll(0, base);
    f.stamp(cel, sprite.width, sprite.height, r.left, r.top);
    selection = Rect(r.left, r.top, r.left + f.w, r.top + f.h);
    _changed();
  }

  /// Drops lifted pixels where they are (one undo step).
  void commitFloating() {
    if (_floating == null) return;
    final before = _before!;
    _floating = null;
    _floatOrigin = null;
    _before = null;
    if (!listEquals(before, cel)) {
      _push(_CelUndo(frame, layer, before, Uint32List.fromList(cel)));
    }
  }

  void selectAll() {
    commitFloating();
    selection = Rect(0, 0, sprite.width, sprite.height);
    notifyListeners();
  }

  void deselect() {
    commitFloating();
    selection = null;
    notifyListeners();
  }

  /// Applies a change to the selected pixels (or the whole layer).
  void _transformSelection(PixelPatch Function(PixelPatch p) op) {
    final s = selection ?? Rect(0, 0, sprite.width, sprite.height);
    if (_floating == null) {
      _before = Uint32List.fromList(cel);
      _floating = PixelPatch.copy(cel, sprite.width, s);
      _floatOrigin = s;
    }
    _floating = op(_floating!);
    _setFloatingAt(
      Rect(s.left, s.top, s.left + _floating!.w, s.top + _floating!.h),
    );
    if (selection == null ||
        (s.left == 0 &&
            s.top == 0 &&
            s.width == sprite.width &&
            s.height == sprite.height)) {
      commitFloating();
    }
  }

  void flipX() => _transformSelection((p) => p.flippedX());
  void flipY() => _transformSelection((p) => p.flippedY());
  void rotate() => _transformSelection((p) => p.rotated());

  void deleteSelection() {
    final s = selection;
    if (s == null) return;
    commitFloating();
    final before = Uint32List.fromList(cel);
    clearRect(cel, sprite.width, s);
    _push(_CelUndo(frame, layer, before, Uint32List.fromList(cel)));
    _changed();
  }

  void copySelection() {
    final s = selection ?? Rect(0, 0, sprite.width, sprite.height);
    commitFloating();
    clipboard = PixelPatch.copy(cel, sprite.width, s);
    notifyListeners();
  }

  /// Pastes at the top-left as a floating selection the user can move.
  void paste() {
    final p = clipboard;
    if (p == null) return;
    commitFloating();
    tool = Tool.select;
    _before = Uint32List.fromList(cel);
    _floating = p;
    _floatOrigin = const Rect(0, 0, 0, 0);
    _setFloatingAt(Rect(0, 0, p.w, p.h));
  }

  // ---- Layers ----

  void addLayer() => _structural(() {
    sprite.addLayer('Layer ${sprite.layers.length + 1}', at: layer + 1);
    layer++;
  });

  void removeLayer(int i) => _structural(() {
    sprite.removeLayer(i);
    if (layer >= i && layer > 0) layer--;
  });

  void duplicateLayer(int i) => _structural(() {
    sprite.duplicateLayer(i);
    layer = i + 1;
  });

  void mergeDown(int i) => _structural(() {
    sprite.mergeDown(i);
    layer = i - 1;
  });

  void moveLayer(int from, int to) => _structural(() {
    sprite.moveLayer(from, to);
    layer = to;
  });

  void selectLayer(int i) {
    commitFloating();
    layer = i;
    notifyListeners();
  }

  void setLayerVisible(int i, bool v) {
    sprite.layers[i].visible = v;
    _changed();
  }

  void setLayerOpacity(int i, double o) {
    sprite.layers[i].opacity = o;
    _changed();
  }

  void renameLayer(int i, String n) {
    sprite.layers[i].name = n;
    notifyListeners();
  }

  // ---- Whole sprite ----

  void load(Sprite s, String n) {
    sprite = s;
    name = n;
    frame = 0;
    layer = 0;
    selection = null;
    _floating = null;
    _undo.clear();
    _redo.clear();
    version++;
    dirty = false;
    notifyListeners();
  }

  void resize(int w, int h) => _structural(() => sprite = sprite.resized(w, h));

  /// Every pixel snapped to the nearest colour of the palette.
  void reduceToPalette() => _structural(() {
    for (final f in sprite.frames) {
      for (final c in f.cels) {
        for (var i = 0; i < c.length; i++) {
          if (c[i] != 0) c[i] = palette.nearest(c[i]);
        }
      }
    }
  });

  Palette paletteFromSprite() {
    final used = sprite.usedColors();
    return Palette('$name colours', used.take(256).toList());
  }

  void markSaved() {
    dirty = false;
    notifyListeners();
  }
}
