import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloth_effect/cloth_effect.dart';

void drag(
  ClothSimulation sim,
  Offset from,
  Offset to, {
  int frames = 14,
  int holdFrames = 20,
}) {
  sim.grab(from);
  for (int i = 1; i <= frames; i++) {
    sim.dragTo(Offset.lerp(from, to, i / frames)!);
    sim.advance(1 / 60);
  }
  for (int i = 0; i < holdFrames; i++) {
    sim.advance(1 / 60);
  }
}

void main() {
  group('ClothSimulation', () {
    test('is taped up before it has been laid out', () {
      final ClothSimulation sim = ClothSimulation();
      expect(sim.pinsIn, isTrue);
      expect(sim.onTheWall, isTrue);
      expect(ClothController().pinsIn, isTrue);
    });

    test('starts flat, asleep and pinned', () {
      final ClothSimulation sim = ClothSimulation()
        ..resize(const Size(400, 800));
      expect(sim.awake, isFalse);
      expect(sim.pinsIn, isTrue);
      expect(sim.onTheWall, isTrue);
      expect(sim.dismissed, isFalse);
      for (int n = 0; n < sim.nodeCount; n++) {
        expect(sim.px[n], sim.rx[n]);
        expect(sim.py[n], sim.ry[n]);
      }
    });

    test('an ordinary drag deforms the sheet and flows back', () {
      final ClothSimulation sim = ClothSimulation()
        ..resize(const Size(400, 800));
      drag(sim, const Offset(190, 280), const Offset(250, 380));
      expect(sim.awake, isTrue);

      final int grabbed = sim.nodeAt(const Offset(190, 280));
      final double lifted = math.sqrt(
        math.pow(sim.px[grabbed] - sim.rx[grabbed], 2) +
            math.pow(sim.py[grabbed] - sim.ry[grabbed], 2) +
            math.pow(sim.pz[grabbed] - sim.rz[grabbed], 2),
      );
      expect(lifted, greaterThan(20), reason: 'should pull clear of the wall');
      final double lag =
          (Offset(sim.px[grabbed], sim.py[grabbed]) - const Offset(250, 380))
              .distance;
      expect(lag, greaterThan(15), reason: 'fabric should lag the pointer');

      sim.release();
      for (int i = 0; i < 900 && sim.awake; i++) {
        sim.advance(1 / 60);
      }
      expect(sim.awake, isFalse, reason: 'should settle and go to sleep');
      expect(sim.pinsIn, isTrue, reason: 'a normal drag must not tear it down');
      expect(sim.onTheWall, isTrue);
      for (int n = 0; n < sim.nodeCount; n++) {
        expect(sim.px[n], sim.rx[n]);
        expect(sim.py[n], sim.ry[n]);
      }
    });

    test('a hard sustained drag rips the screen off the wall', () {
      final ClothSimulation sim = ClothSimulation()
        ..resize(const Size(400, 800));
      drag(
        sim,
        const Offset(190, 260),
        const Offset(340, 620),
        frames: 30,
        holdFrames: 150,
      );
      expect(sim.pinsIn, isFalse, reason: 'the pins should have torn out');
      sim.release();
      for (int i = 0; i < 1500 && !sim.dismissed; i++) {
        sim.advance(1 / 60);
      }
      expect(sim.dismissed, isTrue);
      expect(sim.onTheWall, isFalse);
    });

    test('the weave stays near-inextensible under a hard drag', () {
      final ClothSimulation sim = ClothSimulation()
        ..resize(const Size(400, 800));
      drag(
        sim,
        const Offset(200, 300),
        const Offset(400, 700),
        frames: 40,
        holdFrames: 0,
      );
      final double cw = 400 / sim.cols;
      double maxStrain = 0;
      for (int j = 0; j < sim.ny; j++) {
        for (int i = 0; i < sim.cols; i++) {
          final int a = j * sim.nx + i;
          final int b = a + 1;
          final double dx = sim.px[b] - sim.px[a];
          final double dy = sim.py[b] - sim.py[a];
          final double dz = sim.pz[b] - sim.pz[a];
          final double d = math.sqrt(dx * dx + dy * dy + dz * dz);
          maxStrain = math.max(maxStrain, (d - cw) / cw);
        }
      }
      expect(maxStrain, lessThan(0.35));
    });

    test('pulling the pins leaves it hanging until something tugs it', () {
      final ClothSimulation sim = ClothSimulation()
        ..resize(const Size(400, 800));
      sim.pullPins();
      expect(sim.pinsIn, isFalse);
      expect(sim.awake, isFalse, reason: 'stays put until disturbed');
      expect(sim.onTheWall, isTrue, reason: 'tape still holds it, just weakly');

      drag(sim, const Offset(200, 200), const Offset(260, 420));
      sim.release();
      for (int i = 0; i < 900 && !sim.dismissed; i++) {
        sim.advance(1 / 60);
      }
      expect(sim.dismissed, isTrue);
      expect(sim.awake, isFalse);
    });

    test('reset re-pins the sheet flat', () {
      final ClothSimulation sim = ClothSimulation()
        ..resize(const Size(400, 800));
      sim.pullPins();
      drag(sim, const Offset(200, 200), const Offset(220, 500));
      sim.release();
      for (int i = 0; i < 900 && !sim.dismissed; i++) {
        sim.advance(1 / 60);
      }
      expect(sim.dismissed, isTrue);
      sim.reset();
      expect(sim.dismissed, isFalse);
      expect(sim.pinsIn, isTrue);
      expect(sim.onTheWall, isTrue);
      expect(sim.py[sim.nodeCount - 1], sim.ry[sim.nodeCount - 1]);
    });
  });

  group('Cloth widget', () {
    testWidgets('drag wakes the sheet, release settles it', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final ClothController controller = ClothController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Cloth(
            controller: controller,
            child: const ColoredBox(color: Color(0xFF203040)),
          ),
        ),
      );

      expect(controller.simulation.awake, isFalse);
      final TestGesture gesture = await tester.startGesture(
        const Offset(200, 300),
      );
      await gesture.moveBy(const Offset(40, 60));
      await tester.pump();
      expect(controller.simulation.awake, isTrue);

      await gesture.up();
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(controller.simulation.awake, isFalse);
    });
  });
}
