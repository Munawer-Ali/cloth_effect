import 'dart:typed_data';

import 'package:cloth_effect/cloth_effect.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(ClothController controller, {Widget? child}) {
  return MaterialApp(
    home: Scaffold(
      body: Cloth(
        controller: controller,
        child: child ?? const Center(child: Text('screen')),
      ),
    ),
  );
}

final Uint8List _onePixelPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  testWidgets('the child stays live and tappable while the sheet is at rest', (
    WidgetTester tester,
  ) async {
    final ClothController controller = ClothController();
    addTearDown(controller.dispose);
    int taps = 0;
    await tester.pumpWidget(
      _wrap(
        controller,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const Center(child: Text('screen')),
        ),
      ),
    );

    expect(find.text('screen'), findsOneWidget);
    expect(controller.simulation.awake, isFalse);

    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    expect(taps, 1, reason: 'a resting sheet is just the widget');
  });

  testWidgets('the child stops receiving pointers while the sheet moves', (
    WidgetTester tester,
  ) async {
    final ClothController controller = ClothController();
    addTearDown(controller.dispose);
    int taps = 0;
    await tester.pumpWidget(
      _wrap(
        controller,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const Center(child: Text('screen')),
        ),
      ),
    );

    final TestGesture gesture = await tester.startGesture(
      const Offset(200, 300),
    );
    await gesture.moveBy(const Offset(50, 70));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(controller.simulation.awake, isTrue);

    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    expect(taps, 0, reason: 'fabric in motion is not a button');

    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    expect(taps, 1, reason: 'and it hands control back once it settles');
  });

  testWidgets('knockOff takes the sheet down without a pointer', (
    WidgetTester tester,
  ) async {
    final ClothController controller = ClothController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_wrap(controller));

    expect(controller.pinsIn, isTrue);
    controller.knockOff();
    await tester.pump();
    expect(controller.pinsIn, isFalse);

    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(controller.dismissed, isTrue);
  });

  testWidgets('reset puts a dismissed sheet back', (WidgetTester tester) async {
    final ClothController controller = ClothController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_wrap(controller));

    controller.knockOff();
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(controller.dismissed, isTrue);

    controller.reset();
    await tester.pump();
    expect(controller.dismissed, isFalse);
    expect(controller.pinsIn, isTrue);
    expect(controller.simulation.onTheWall, isTrue);
  });

  testWidgets('notifies listeners when the sheet comes to rest', (
    WidgetTester tester,
  ) async {
    final ClothController controller = ClothController();
    addTearDown(controller.dispose);
    int notifications = 0;
    controller.addListener(() => notifications++);
    await tester.pumpWidget(_wrap(controller));

    final TestGesture gesture = await tester.startGesture(
      const Offset(200, 300),
    );
    await gesture.moveBy(const Offset(40, 60));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    expect(notifications, greaterThan(0));
    expect(controller.simulation.awake, isFalse);
  });

  testWidgets('accepts a pre-configured simulation', (
    WidgetTester tester,
  ) async {
    final ClothController controller = ClothController(
      simulation: ClothSimulation(cols: 8, rows: 12)..anchorToughness = 40,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_wrap(controller));

    expect(controller.simulation.cols, 8);
    expect(controller.simulation.nodeCount, 9 * 13);
    expect(controller.pinsIn, isTrue);
  });

  testWidgets('Cloth.image hangs a picture on the wall', (
    WidgetTester tester,
  ) async {
    final ClothController controller = ClothController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Cloth.image(
            controller: controller,
            image: MemoryImage(_onePixelPng),
            fit: BoxFit.contain,
          ),
        ),
      ),
    );

    final Image image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
    expect(image.fit, BoxFit.contain);
    expect(controller.pinsIn, isTrue);

    final TestGesture gesture = await tester.startGesture(
      const Offset(200, 300),
    );
    await gesture.moveBy(const Offset(50, 70));
    await tester.pump();
    expect(controller.simulation.awake, isTrue);
    await gesture.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposes cleanly mid-animation', (WidgetTester tester) async {
    final ClothController controller = ClothController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_wrap(controller));

    final TestGesture gesture = await tester.startGesture(
      const Offset(200, 300),
    );
    await gesture.moveBy(const Offset(60, 90));
    await tester.pump();
    expect(controller.simulation.awake, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await gesture.up();
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives a resize', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final ClothController controller = ClothController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_wrap(controller));
    final Size first = controller.simulation.size;

    tester.view.physicalSize = const Size(1290, 2796);
    await tester.pumpAndSettle();
    expect(controller.simulation.size, isNot(first));
    expect(controller.pinsIn, isTrue);
    expect(tester.takeException(), isNull);
  });
}
