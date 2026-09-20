import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

/// A Verlet mass-spring cloth hanging in 3D in front of a wall.
///
/// The grid is [cols] + 1 by [rows] + 1 nodes. The wall is the plane `z == 0`
/// and the viewer sits at negative z, so fabric lifted toward the camera has
/// negative z. The top edge is taped to the wall; everything below hangs from
/// it. Each anchor wears out under sustained load, so a hard enough pull tears
/// the sheet off the wall.
///
/// Positions are in logical pixels, relative to the top left of the box the
/// cloth occupies.
class ClothSimulation {
  /// Creates a cloth with a [cols] by [rows] grid of quads.
  ///
  /// Higher resolutions give finer folds at proportionally more cost. Below
  /// roughly 24 by 36 the folds become too coarse to read as fabric.
  ClothSimulation({this.cols = 28, this.rows = 42}) {
    final int count = (cols + 1) * (rows + 1);
    px = Float32List(count);
    py = Float32List(count);
    pz = Float32List(count);
    _ox = Float32List(count);
    _oy = Float32List(count);
    _oz = Float32List(count);
    rx = Float32List(count);
    ry = Float32List(count);
    rz = Float32List(count);
    pinned = Uint8List(count);
    held = Uint8List(count);
    _bond = Float32List(count);
    _load = Float32List(count);
    _holdDx = Float32List(count);
    _holdDy = Float32List(count);
    _buildSprings();
    _anchorTop();
  }

  /// Quads across.
  final int cols;

  /// Quads down.
  final int rows;

  /// Nodes across.
  int get nx => cols + 1;

  /// Nodes down.
  int get ny => rows + 1;

  /// Total node count.
  int get nodeCount => nx * ny;

  /// Current node positions.
  late final Float32List px;

  /// Current node positions.
  late final Float32List py;

  /// Current node positions.
  late final Float32List pz;

  late final Float32List _ox;
  late final Float32List _oy;
  late final Float32List _oz;

  /// Rest positions, where the sheet sits flat against the wall.
  late final Float32List rx;

  /// Rest positions, where the sheet sits flat against the wall.
  late final Float32List ry;

  /// Rest depth. A hair of smooth sub-pixel undulation, so fabric under
  /// compression has a direction to buckle in.
  late final Float32List rz;

  /// 1 for nodes of the top edge that are still attached to the wall.
  late final Uint8List pinned;

  /// 1 for nodes currently gripped by the pointer.
  late final Uint8List held;

  late final Float32List _bond;
  late final Float32List _load;
  late final Float32List _holdDx;
  late final Float32List _holdDy;

  late final Int32List _sa;
  late final Int32List _sb;
  late final Float32List _srest;
  late final Float32List _sk;
  late int _structuralEnd;

  /// Downward acceleration, in logical px/s².
  double gravity = 2400;

  /// Fraction of its weight that fabric still lying against the wall keeps.
  ///
  /// A sheet flat against a wall is mostly held up by the wall, not by the tape
  /// along its top. Without this the tape carries everything and peels off
  /// under the sheet's own weight. Fabric lifted clear feels all of its weight,
  /// so pulling a fold out from the wall is what loads the tape.
  double wallSupport = 0.06;

  /// How far a node must come off the wall to stop being supported by it.
  double contactDepth = 3;

  /// Cling to the wall the sheet lies against, per substep².
  ///
  /// Not what holds the sheet up. Just enough that it comes to rest exactly on
  /// its rest position rather than drifting.
  double wallCling = 0.0015;

  /// Velocity retention per substep while the sheet still hangs from the wall.
  ///
  /// Heavy, so the fabric settles back without overshooting.
  double pinnedFriction = 0.86;

  /// Velocity retention per substep once the sheet is falling.
  double freeFriction = 0.995;

  /// Constraint relaxation passes per substep.
  int iterations = 8;

  /// Resistance to curvature, which sets the fold wavelength.
  ///
  /// Higher gives broader, smoother folds; lower gives finer creases.
  double bendStiffness = 0.14;

  /// Hard ceiling on how far the weave may stretch, as a fraction of rest.
  ///
  /// Real fabric stretches a few percent and then refuses, so it gathers into
  /// folds instead and has no stored energy to give back on release. This is
  /// the largest single lever on whether the result reads as cloth or rubber.
  double maxStretch = 0.04;

  /// Relaxation passes for [maxStretch].
  int strainIterations = 12;

  /// How firmly a pinch pulls the fabric toward the pointer, per substep².
  ///
  /// A spring rather than a hard constraint, so the weave can go taut and the
  /// finger slide on past it.
  double grabStiffness = 0.08;

  /// Velocity retention for gripped nodes.
  double grabDamping = 0.5;

  /// How far toward the viewer a pinch lifts the fabric, in logical px.
  double grabDepth = 130;

  /// Radius of a pinch, in logical px.
  ///
  /// Gripping a single point pulls the fabric out into a needle.
  double grabRadius = 38;

  /// Load one anchor shrugs off entirely, per substep.
  double anchorYield = 0.9;

  /// Accumulated load one anchor survives before it lets go.
  ///
  /// Ordinary drags never reach it; a hard pull tears it in about a second.
  double anchorToughness = 2500;

  /// Per-substep recovery for an anchor that is not being pulled on.
  double anchorHealing = 0.985;

  /// Fraction of the top edge that must tear before the rest gives way.
  double pinReleaseFraction = 0.35;

  /// How much weaker the anchors are once [pullPins] has been called.
  double pulledPinsWeakening = 8;

  Size _size = Size.zero;

  /// The box the cloth currently occupies.
  Size get size => _size;

  bool _weakened = false;
  int _anchorsLeft = 0;

  /// Whether the sheet is still pinned up.
  ///
  /// False once [pullPins] has been called, or the anchors have torn out.
  bool get pinsIn => !_weakened && _anchorsLeft > 0;

  /// Whether any of the top edge is still attached to the wall.
  bool get onTheWall => _anchorsLeft > 0;

  bool _awake = false;

  /// Whether the cloth still needs simulating, and therefore mesh rendering.
  bool get awake => _awake;

  bool _dismissed = false;

  /// Whether the sheet has fallen clear of the box.
  bool get dismissed => _dismissed;

  bool _holding = false;

  /// Whether a pointer is currently gripping the fabric.
  bool get isHeld => _holding;

  Offset _pointer = Offset.zero;
  Offset _grabbedAt = Offset.zero;

  static const double _dt = 1 / 120;
  double _accumulator = 0;
  int _still = 0;

  void _buildSprings() {
    final List<int> a = <int>[];
    final List<int> b = <int>[];
    final List<double> k = <double>[];

    void link(int i0, int j0, int i1, int j1, double stiffness) {
      if (i1 < 0 || i1 >= nx || j1 < 0 || j1 >= ny) {
        return;
      }
      a.add(j0 * nx + i0);
      b.add(j1 * nx + i1);
      k.add(stiffness);
    }

    for (int j = 0; j < ny; j++) {
      for (int i = 0; i < nx; i++) {
        link(i, j, i + 1, j, 1);
        link(i, j, i, j + 1, 1);
      }
    }
    _structuralEnd = a.length;
    for (int j = 0; j < ny; j++) {
      for (int i = 0; i < nx; i++) {
        link(i, j, i + 1, j + 1, 0.5);
        link(i, j, i - 1, j + 1, 0.5);
      }
    }

    _sa = Int32List.fromList(a);
    _sb = Int32List.fromList(b);
    _sk = Float32List.fromList(k);
    _srest = Float32List(a.length);
  }

  /// Lays the grid out over [value] and returns the sheet to the wall, flat.
  void resize(Size value) {
    if (value == _size || value.isEmpty) {
      return;
    }
    _size = value;
    final double cw = value.width / cols;
    final double ch = value.height / rows;
    for (int j = 0; j < ny; j++) {
      for (int i = 0; i < nx; i++) {
        final int n = j * nx + i;
        rx[n] = i * cw;
        ry[n] = j * ch;
        rz[n] =
            -0.02 *
            (math.sin(i * 0.17) * math.sin(j * 0.13) +
                0.5 * math.sin(i * 0.07 + j * 0.11));
      }
    }
    for (int s = 0; s < _sa.length; s++) {
      final int a = _sa[s];
      final int b = _sb[s];
      final double dx = rx[b] - rx[a];
      final double dy = ry[b] - ry[a];
      _srest[s] = math.sqrt(dx * dx + dy * dy);
    }
    reset();
  }

  /// Tapes the sheet back up, flat and undamaged.
  void reset() {
    px.setAll(0, rx);
    py.setAll(0, ry);
    pz.setAll(0, rz);
    _ox.setAll(0, rx);
    _oy.setAll(0, ry);
    _oz.setAll(0, rz);
    _dismissed = false;
    _awake = false;
    _holding = false;
    held.fillRange(0, held.length, 0);
    _still = 0;
    _accumulator = 0;
    _bond.fillRange(0, _bond.length, 0);
    _weakened = false;
    _anchorTop();
  }

  void _anchorTop() {
    pinned.fillRange(0, pinned.length, 0);
    for (int i = 0; i < nx; i++) {
      pinned[i] = 1;
    }
    _anchorsLeft = nx;
  }

  void _popPins() {
    pinned.fillRange(0, pinned.length, 0);
    _anchorsLeft = 0;
  }

  /// Weakens the anchors by [pulledPinsWeakening].
  ///
  /// The sheet stays where it is until something pulls at it, but almost
  /// anything will then take it down. Dragging hard achieves the same thing
  /// without this.
  void pullPins() {
    _weakened = true;
  }

  /// Tears the sheet off the wall at once, with no pointer involved.
  void unstickAll() {
    _popPins();
    _weakened = true;
    wake();
  }

  /// Resumes simulating.
  void wake() {
    if (_dismissed) {
      return;
    }
    _awake = true;
    _still = 0;
  }

  /// The node nearest to [point].
  int nodeAt(Offset point) {
    final double cw = _size.width / cols;
    final double ch = _size.height / rows;
    final int i = (point.dx / cw).round().clamp(0, nx - 1);
    final int j = (point.dy / ch).round().clamp(0, ny - 1);
    return j * nx + i;
  }

  /// Pinches the fabric at [point].
  ///
  /// Every node within [grabRadius] follows the pointer, keeping its spacing,
  /// and lifts away from the wall.
  void grab(Offset point) {
    if (_dismissed) {
      return;
    }
    held.fillRange(0, held.length, 0);
    final double r2 = grabRadius * grabRadius;
    int count = 0;
    for (int n = 0; n < nodeCount; n++) {
      final double dx = px[n] - point.dx;
      final double dy = py[n] - point.dy;
      if (dx * dx + dy * dy > r2) {
        continue;
      }
      held[n] = 1;
      _holdDx[n] = dx;
      _holdDy[n] = dy;
      count++;
    }
    if (count == 0) {
      final int n = nodeAt(point);
      held[n] = 1;
      _holdDx[n] = 0;
      _holdDy[n] = 0;
    }
    _holding = true;
    _pointer = point;
    _grabbedAt = point;
    wake();
  }

  /// Moves the pinch to [point].
  void dragTo(Offset point) {
    _pointer = point;
  }

  /// Lets go of the fabric.
  void release() {
    _holding = false;
    held.fillRange(0, held.length, 0);
  }

  /// Advances the simulation by [seconds] of wall-clock time.
  ///
  /// Steps at a fixed 120 Hz with an accumulator, so behaviour does not change
  /// with display refresh rate.
  void advance(double seconds) {
    if (!_awake || _size.isEmpty) {
      return;
    }
    _accumulator += math.min(seconds, 0.05);
    while (_accumulator >= _dt) {
      _substep();
      _accumulator -= _dt;
      if (!_awake) {
        _accumulator = 0;
        break;
      }
    }
  }

  void _substep() {
    final double g = gravity * _dt * _dt;
    final double lift = _holding
        ? -grabDepth * math.min(1, (_pointer - _grabbedAt).distance / 90)
        : 0;
    final bool anchored = _anchorsLeft > 0;

    for (int n = 0; n < nodeCount; n++) {
      if (pinned[n] == 1) {
        continue;
      }
      final bool grabbed = held[n] == 1;
      final double damping = grabbed
          ? grabDamping
          : (anchored ? pinnedFriction : freeFriction);
      double vx = (px[n] - _ox[n]) * damping;
      double vy = (py[n] - _oy[n]) * damping;
      double vz = (pz[n] - _oz[n]) * damping;
      if (grabbed) {
        vx += (_pointer.dx + _holdDx[n] - px[n]) * grabStiffness;
        vy += (_pointer.dy + _holdDy[n] - py[n]) * grabStiffness;
        vz += (lift - pz[n]) * grabStiffness;
      }
      if (anchored && wallCling > 0) {
        vx += (rx[n] - px[n]) * wallCling;
        vy += (ry[n] - py[n]) * wallCling;
        vz += (rz[n] - pz[n]) * wallCling;
      }
      _ox[n] = px[n];
      _oy[n] = py[n];
      _oz[n] = pz[n];
      px[n] += vx;
      py[n] += vy + (pz[n] > -contactDepth ? g * wallSupport : g);
      pz[n] += vz;
    }

    if (anchored) {
      _load.fillRange(0, _load.length, 0);
    }
    for (int it = 0; it < iterations; it++) {
      _solve();
    }
    _bend();
    for (int it = 0; it < strainIterations; it++) {
      _limitStrain();
    }

    for (int n = 0; n < nodeCount; n++) {
      if (pz[n] > 0) {
        pz[n] = 0;
      }
    }

    _wearAnchors();
    _checkSettled();
  }

  void _solve() {
    for (int s = 0; s < _sa.length; s++) {
      final int a = _sa[s];
      final int b = _sb[s];
      final bool fa = pinned[a] == 1;
      final bool fb = pinned[b] == 1;
      if (fa && fb) {
        continue;
      }
      final double dx = px[b] - px[a];
      final double dy = py[b] - py[a];
      final double dz = pz[b] - pz[a];
      final double d = math.sqrt(dx * dx + dy * dy + dz * dz);
      if (d < 1e-6) {
        continue;
      }
      final double diff = (d - _srest[s]) / d * _sk[s];
      if (fa) {
        px[b] -= dx * diff;
        py[b] -= dy * diff;
        pz[b] -= dz * diff;
        _load[a] += (d - _srest[s]).abs() * _sk[s];
      } else if (fb) {
        px[a] += dx * diff;
        py[a] += dy * diff;
        pz[a] += dz * diff;
        _load[b] += (d - _srest[s]).abs() * _sk[s];
      } else {
        final double hx = dx * diff * 0.5;
        final double hy = dy * diff * 0.5;
        final double hz = dz * diff * 0.5;
        px[a] += hx;
        py[a] += hy;
        pz[a] += hz;
        px[b] -= hx;
        py[b] -= hy;
        pz[b] -= hz;
      }
    }
  }

  void _bend() {
    for (int j = 0; j < ny; j++) {
      for (int i = 1; i < nx - 1; i++) {
        final int n = j * nx + i;
        if (pinned[n] == 1) {
          continue;
        }
        final int a = n - 1;
        final int b = n + 1;
        px[n] += ((px[a] + px[b]) * 0.5 - px[n]) * bendStiffness;
        py[n] += ((py[a] + py[b]) * 0.5 - py[n]) * bendStiffness;
        pz[n] += ((pz[a] + pz[b]) * 0.5 - pz[n]) * bendStiffness;
      }
    }
    for (int j = 1; j < ny - 1; j++) {
      for (int i = 0; i < nx; i++) {
        final int n = j * nx + i;
        if (pinned[n] == 1) {
          continue;
        }
        final int a = n - nx;
        final int b = n + nx;
        px[n] += ((px[a] + px[b]) * 0.5 - px[n]) * bendStiffness;
        py[n] += ((py[a] + py[b]) * 0.5 - py[n]) * bendStiffness;
        pz[n] += ((pz[a] + pz[b]) * 0.5 - pz[n]) * bendStiffness;
      }
    }
  }

  void _limitStrain() {
    for (int s = 0; s < _structuralEnd; s++) {
      final int a = _sa[s];
      final int b = _sb[s];
      final bool fa = pinned[a] == 1;
      final bool fb = pinned[b] == 1;
      if (fa && fb) {
        continue;
      }
      final double limit = _srest[s] * (1 + maxStretch);
      final double dx = px[b] - px[a];
      final double dy = py[b] - py[a];
      final double dz = pz[b] - pz[a];
      final double d = math.sqrt(dx * dx + dy * dy + dz * dz);
      if (d <= limit || d < 1e-6) {
        continue;
      }
      final double pull = (d - limit) / d;
      if (fa) {
        px[b] -= dx * pull;
        py[b] -= dy * pull;
        pz[b] -= dz * pull;
      } else if (fb) {
        px[a] += dx * pull;
        py[a] += dy * pull;
        pz[a] += dz * pull;
      } else {
        final double hx = dx * pull * 0.5;
        final double hy = dy * pull * 0.5;
        final double hz = dz * pull * 0.5;
        px[a] += hx;
        py[a] += hy;
        pz[a] += hz;
        px[b] -= hx;
        py[b] -= hy;
        pz[b] -= hz;
      }
    }
  }

  void _wearAnchors() {
    if (_anchorsLeft == 0) {
      return;
    }
    final double toughness = _weakened
        ? anchorToughness / pulledPinsWeakening
        : anchorToughness;
    for (int n = 0; n < nodeCount; n++) {
      if (pinned[n] == 0) {
        continue;
      }
      if (_load[n] > anchorYield) {
        _bond[n] += _load[n] - anchorYield;
        if (_bond[n] > toughness) {
          pinned[n] = 0;
          _anchorsLeft--;
        }
      } else if (_bond[n] > 0) {
        _bond[n] *= anchorHealing;
      }
    }
    if (_anchorsLeft < nx * (1 - pinReleaseFraction)) {
      _popPins();
    }
  }

  bool get _intact => _anchorsLeft == nx;

  double _offWall() {
    double worst = 0;
    for (int n = 0; n < nodeCount; n++) {
      final double dx = px[n] - rx[n];
      final double dy = py[n] - ry[n];
      final double dz = pz[n] - rz[n];
      worst = math.max(worst, dx * dx + dy * dy + dz * dz);
    }
    return math.sqrt(worst);
  }

  double _netMovement() {
    double moved = 0;
    for (int n = 0; n < nodeCount; n++) {
      if (pinned[n] == 1) {
        continue;
      }
      moved = math.max(
        moved,
        (px[n] - _ox[n]).abs() +
            (py[n] - _oy[n]).abs() +
            (pz[n] - _oz[n]).abs(),
      );
    }
    return moved;
  }

  void _checkSettled() {
    if (_holding) {
      _still = 0;
      return;
    }

    if (!onTheWall) {
      double lowest = double.negativeInfinity;
      for (int n = 0; n < nodeCount; n++) {
        lowest = math.max(lowest, -py[n]);
      }
      if (-lowest > _size.height + 40) {
        _dismissed = true;
        _awake = false;
        _holding = false;
        held.fillRange(0, held.length, 0);
        return;
      }
    }

    if (_intact && _offWall() > 1) {
      _still = 0;
      return;
    }

    if (_netMovement() < 0.03) {
      _still++;
      if (_still > 20) {
        _awake = false;
        if (_intact) {
          px.setAll(0, rx);
          py.setAll(0, ry);
          pz.setAll(0, rz);
          _ox.setAll(0, rx);
          _oy.setAll(0, ry);
          _oz.setAll(0, rz);
        }
      }
    } else {
      _still = 0;
    }
  }
}
