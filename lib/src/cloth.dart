import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'cloth_simulation.dart';

/// Drives a [Cloth] from outside the widget tree.
///
/// Notifies its listeners when the sheet is taken off the wall, put back, or
/// comes to rest, so surrounding UI can react.
class ClothController extends ChangeNotifier {
  /// Creates a controller, optionally wrapping a pre-configured [simulation].
  ClothController({ClothSimulation? simulation})
    : simulation = simulation ?? ClothSimulation();

  /// The cloth being simulated. Its fields are the tuning surface.
  final ClothSimulation simulation;

  /// Whether the sheet is still pinned up.
  bool get pinsIn => simulation.pinsIn;

  /// Whether the sheet has fallen clear of the box.
  bool get dismissed => simulation.dismissed;

  /// Weakens the anchors so the next tug takes the sheet down.
  ///
  /// Not required: a hard enough drag tears the sheet off on its own.
  void pullPins() {
    if (!simulation.pinsIn) {
      return;
    }
    simulation.pullPins();
    notifyListeners();
  }

  /// Tapes the sheet back up, flat and undamaged.
  void reset() {
    simulation.reset();
    notifyListeners();
  }

  /// Resumes simulating without a pointer on the sheet.
  void disturb() {
    simulation.wake();
    notifyListeners();
  }

  /// Takes the sheet off the wall outright, with no pointer involved.
  void knockOff() {
    simulation.unstickAll();
    notifyListeners();
  }

  void _changed() => notifyListeners();
}

/// Renders [child] as a sheet of fabric taped to the wall by its top edge.
///
/// Drag it and the fabric lifts, folds and flows back. Drag hard and hold, and
/// the anchors tear out and the whole thing falls away.
///
/// While the sheet is flat and at rest the real [child] is painted, so it stays
/// crisp and interactive. The first drag past the touch slop snapshots the
/// child into a texture and swaps in a lit, depth-sorted cloth mesh built from
/// that same picture.
///
/// ```dart
/// Cloth(
///   controller: controller,
///   child: const MyScreen(),
/// )
/// ```
class Cloth extends StatefulWidget {
  /// Creates a cloth sheet wrapping [child].
  const Cloth({super.key, required this.controller, required this.child});

  /// Creates a cloth sheet showing [image], for hanging a picture on the wall.
  ///
  /// Shorthand for passing an [Image] as the [child]; anything an
  /// [ImageProvider] can supply works, including assets, files and network
  /// images.
  ///
  /// ```dart
  /// Cloth.image(
  ///   controller: controller,
  ///   image: const AssetImage('assets/poster.jpg'),
  /// )
  /// ```
  Cloth.image({
    super.key,
    required this.controller,
    required ImageProvider image,
    BoxFit fit = BoxFit.cover,
    AlignmentGeometry alignment = Alignment.center,
    FilterQuality filterQuality = FilterQuality.medium,
  }) : child = SizedBox.expand(
         child: Image(
           image: image,
           fit: fit,
           alignment: alignment,
           filterQuality: filterQuality,
         ),
       );

  /// Drives the sheet and reports its state.
  final ClothController controller;

  /// The widget rendered as fabric.
  final Widget child;

  @override
  State<Cloth> createState() => _ClothState();
}

class _ClothState extends State<Cloth> with SingleTickerProviderStateMixin {
  late final ClothSimulation _sim = widget.controller.simulation;
  late final _ClothPainter _painter = _ClothPainter(_sim);
  final SnapshotController _snapshot = SnapshotController();
  late Ticker _ticker;

  Duration _last = Duration.zero;
  bool _passive = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(Cloth oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _ticker.dispose();
    _snapshot.dispose();
    _painter.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (_sim.awake && !_ticker.isActive) {
      _startSimulating();
    }
    _syncPassive();
  }

  void _syncPassive() {
    final bool next = _sim.awake || _sim.dismissed;
    if (next != _passive && mounted) {
      setState(() => _passive = next);
    }
  }

  void _tick(Duration elapsed) {
    final double dt =
        (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    _sim.advance(dt);
    _painter.invalidate();
    _syncPassive();
    if (!_sim.awake) {
      _ticker.stop();
      _last = Duration.zero;
      if (!_sim.dismissed) {
        _snapshot.allowSnapshotting = false;
      }
      widget.controller._changed();
    }
  }

  void _startSimulating() {
    _snapshot.allowSnapshotting = true;
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
    _syncPassive();
  }

  void _onGrab(Offset local) {
    if (_sim.dismissed) {
      return;
    }
    _sim.grab(local);
    _startSimulating();
  }

  void _onDrag(Offset local) => _sim.dragTo(local);

  void _onEnd() => _sim.release();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _sim.resize(constraints.biggest);
        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            _ClothDragRecognizer:
                GestureRecognizerFactoryWithHandlers<_ClothDragRecognizer>(
                  () => _ClothDragRecognizer(slop: kTouchSlop),
                  (_ClothDragRecognizer instance) {
                    instance
                      ..onGrab = _onGrab
                      ..onDrag = _onDrag
                      ..onEnd = _onEnd;
                  },
                ),
          },
          child: IgnorePointer(
            ignoring: _passive,
            child: SnapshotWidget(
              controller: _snapshot,
              painter: _painter,
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

class _ClothPainter extends SnapshotPainter {
  _ClothPainter(this.sim);

  final ClothSimulation sim;

  static const double _focal = 900;

  static const double _lx = -0.448;
  static const double _ly = -0.617;
  static const double _lz = -0.647;

  static const double _hx = -0.247;
  static const double _hy = -0.340;
  static const double _hz = -0.907;

  static const double _diffuseFlat = -_lz;
  static const double _specFlat = 0.00195;

  Float32List? _positions;
  Float32List? _texCoords;
  Int32List? _diffuse;
  Int32List? _specular;
  Uint16List? _indices;
  Float32List? _triDepth;
  Int32List? _order;
  Size _texSize = Size.zero;
  ui.Image? _shaderImage;
  ImageShader? _shader;

  void invalidate() => notifyListeners();

  @override
  void paint(
    PaintingContext context,
    Offset offset,
    Size size,
    PaintingContextCallback painter,
  ) {
    painter(context, offset);
  }

  @override
  void paintSnapshot(
    PaintingContext context,
    Offset offset,
    Size size,
    ui.Image image,
    Size sourceSize,
    double pixelRatio,
  ) {
    if (sim.dismissed || size.isEmpty) {
      return;
    }
    _ensureBuffers(image, size);
    _project(offset, size);
    final double peakSpecular = _shade();
    _sortByDepth();

    final Canvas canvas = context.canvas;
    final ui.Vertices lit = ui.Vertices.raw(
      ui.VertexMode.triangles,
      _positions!,
      textureCoordinates: _texCoords,
      colors: _diffuse,
      indices: _indices,
    );
    canvas.drawVertices(
      lit,
      BlendMode.modulate,
      Paint()
        ..isAntiAlias = false
        ..filterQuality = FilterQuality.low
        ..shader = _shaderFor(image),
    );
    lit.dispose();

    if (peakSpecular > 0.008) {
      final ui.Vertices sheen = ui.Vertices.raw(
        ui.VertexMode.triangles,
        _positions!,
        colors: _specular,
        indices: _indices,
      );
      canvas.drawVertices(
        sheen,
        BlendMode.modulate,
        Paint()
          ..isAntiAlias = false
          ..color = const Color(0xFFFFFFFF)
          ..blendMode = BlendMode.plus,
      );
      sheen.dispose();
    }
  }

  void _project(Offset offset, Size size) {
    final Float32List positions = _positions!;
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    for (int n = 0; n < sim.nodeCount; n++) {
      final double scale = _focal / (_focal + sim.pz[n]);
      positions[n * 2] = cx + (sim.px[n] - cx) * scale + offset.dx;
      positions[n * 2 + 1] = cy + (sim.py[n] - cy) * scale + offset.dy;
    }
  }

  double _shade() {
    final int nx = sim.nx;
    final int ny = sim.ny;
    final Int32List diffuse = _diffuse!;
    final Int32List specular = _specular!;
    double peak = 0;

    for (int j = 0; j < ny; j++) {
      for (int i = 0; i < nx; i++) {
        final int n = j * nx + i;
        final int l = j * nx + (i > 0 ? i - 1 : i);
        final int r = j * nx + (i < nx - 1 ? i + 1 : i);
        final int u = (j > 0 ? j - 1 : j) * nx + i;
        final int d = (j < ny - 1 ? j + 1 : j) * nx + i;

        final double ux = sim.px[r] - sim.px[l];
        final double uy = sim.py[r] - sim.py[l];
        final double uz = sim.pz[r] - sim.pz[l];
        final double vx = sim.px[d] - sim.px[u];
        final double vy = sim.py[d] - sim.py[u];
        final double vz = sim.pz[d] - sim.pz[u];

        double mx = vy * uz - vz * uy;
        double my = vz * ux - vx * uz;
        double mz = vx * uy - vy * ux;
        final double len = math.sqrt(mx * mx + my * my + mz * mz);
        if (len < 1e-9) {
          diffuse[n] = 0xFFFFFFFF;
          specular[n] = 0xFF000000;
          continue;
        }
        mx /= len;
        my /= len;
        mz /= len;

        final bool back = mz > 0;
        if (back) {
          mx = -mx;
          my = -my;
          mz = -mz;
        }

        double lambert = mx * _lx + my * _ly + mz * _lz;
        if (lambert < 0) {
          lambert = 0;
        }
        double shade = 0.42 + 0.58 * (lambert / _diffuseFlat);
        if (back) {
          shade *= 0.5;
        }
        shade = shade.clamp(0.12, 1.0);
        final int g = (shade * 255).round();
        diffuse[n] = 0xFF000000 | (g << 16) | (g << 8) | g;

        int s = 0;
        if (!back) {
          double nh = mx * _hx + my * _hy + mz * _hz;
          if (nh > 0) {
            nh *= nh;
            nh *= nh;
            nh *= nh;
            nh *= nh;
            nh *= nh;
            nh *= nh;
            final double sheen = (nh - _specFlat) * 0.34;
            if (sheen > 0) {
              if (sheen > peak) {
                peak = sheen;
              }
              s = (sheen * 255).round().clamp(0, 255);
            }
          }
        }
        specular[n] = 0xFF000000 | (s << 16) | (s << 8) | s;
      }
    }
    return peak;
  }

  void _sortByDepth() {
    final int nx = sim.nx;
    final Float32List depth = _triDepth!;
    final Int32List order = _order!;
    final Uint16List indices = _indices!;

    int t = 0;
    for (int j = 0; j < sim.rows; j++) {
      for (int i = 0; i < sim.cols; i++) {
        final int a = j * nx + i;
        final int b = a + 1;
        final int c = a + nx;
        final int e = c + 1;
        depth[t++] = sim.pz[a] + sim.pz[b] + sim.pz[c];
        depth[t++] = sim.pz[b] + sim.pz[e] + sim.pz[c];
      }
    }

    order.sort((int p, int q) => depth[q].compareTo(depth[p]));

    for (int k = 0; k < order.length; k++) {
      final int tri = order[k];
      final int cell = tri >> 1;
      final int i = cell % sim.cols;
      final int j = cell ~/ sim.cols;
      final int a = j * nx + i;
      final int b = a + 1;
      final int c = a + nx;
      final int e = c + 1;
      final int o = k * 3;
      if (tri.isEven) {
        indices[o] = a;
        indices[o + 1] = b;
        indices[o + 2] = c;
      } else {
        indices[o] = b;
        indices[o + 1] = e;
        indices[o + 2] = c;
      }
    }
  }

  ImageShader _shaderFor(ui.Image image) {
    if (identical(_shaderImage, image) && _shader != null) {
      return _shader!;
    }
    _shader?.dispose();
    _shaderImage = image;
    return _shader = ImageShader(
      image,
      TileMode.clamp,
      TileMode.clamp,
      Matrix4.identity().storage,
      filterQuality: FilterQuality.low,
    );
  }

  void _ensureBuffers(ui.Image image, Size size) {
    final int n = sim.nodeCount;
    final int triangles = sim.cols * sim.rows * 2;
    _positions ??= Float32List(n * 2);
    _diffuse ??= Int32List(n);
    _specular ??= Int32List(n);
    _indices ??= Uint16List(triangles * 3);
    _triDepth ??= Float32List(triangles);
    _order ??= Int32List.fromList(List<int>.generate(triangles, (int i) => i));

    final Size texSize = Size(image.width.toDouble(), image.height.toDouble());
    if (_texCoords == null || _texSize != texSize) {
      _texSize = texSize;
      final Float32List tex = Float32List(n * 2);
      final double sx = texSize.width / size.width;
      final double sy = texSize.height / size.height;
      for (int k = 0; k < n; k++) {
        tex[k * 2] = sim.rx[k] * sx;
        tex[k * 2 + 1] = sim.ry[k] * sy;
      }
      _texCoords = tex;
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }

  @override
  bool shouldRepaint(covariant _ClothPainter oldPainter) => true;
}

class _ClothDragRecognizer extends OneSequenceGestureRecognizer {
  _ClothDragRecognizer({required this.slop});

  final double slop;

  ValueChanged<Offset>? onGrab;
  ValueChanged<Offset>? onDrag;
  VoidCallback? onEnd;

  int? _pointer;
  Offset _down = Offset.zero;
  Offset _previous = Offset.zero;
  double _travelled = 0;
  bool _grabbed = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointer != null) {
      return;
    }
    _pointer = event.pointer;
    _down = event.localPosition;
    _previous = _down;
    _travelled = 0;
    _grabbed = false;
    startTrackingPointer(event.pointer, event.transform);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    if (event is PointerMoveEvent) {
      _travelled += (event.localPosition - _previous).distance;
      _previous = event.localPosition;
      if (!_grabbed && _travelled > slop) {
        _grabbed = true;
        resolve(GestureDisposition.accepted);
        onGrab?.call(_down);
      }
      if (_grabbed) {
        onDrag?.call(event.localPosition);
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    if (_grabbed) {
      onEnd?.call();
    }
    _pointer = null;
    _grabbed = false;
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer == _pointer) {
      stopTrackingPointer(pointer);
    }
    super.rejectGesture(pointer);
  }

  @override
  String get debugDescription => 'cloth drag';
}
