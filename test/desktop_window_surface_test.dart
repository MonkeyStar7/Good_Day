import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/desktop_window_surface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'modal dialogs and nested popups preserve the underlying silhouette',
    () async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(DesktopWindowSurface.channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          DesktopWindowSurface.channel,
          null,
        ),
      );
      final surface = DesktopWindowSurface();
      final observer = WindowSurfaceObserver(surface);
      final page = MaterialPageRoute<void>(builder: (_) => const SizedBox());
      final popup = RawDialogRoute<void>(
        pageBuilder: (_, _, _) => const SizedBox(),
      );
      final nested = RawDialogRoute<void>(
        pageBuilder: (_, _, _) => const SizedBox(),
      );
      observer.didPush(popup, page);
      observer.didPush(nested, popup);
      observer.didPop(nested, popup);
      await Future<void>.delayed(Duration.zero);
      expect(surface.notesVisible, isTrue);
      expect(calls, isEmpty);
      surface.notesVisible = false;
      observer.didPush(nested, popup);
      observer.didPop(nested, popup);
      await Future<void>.delayed(Duration.zero);
      expect(surface.notesVisible, isFalse);
      expect(calls, isEmpty);
    },
  );
  test(
    'outer window grows and shrinks with the content, retaining its right edge',
    () {
      const original = Rect.fromLTWH(900, 24, 456, 720);
      const work = Rect.fromLTWH(0, 0, 2000, 1800);
      final large = scaledWindowBounds(original, 1, 1.5, work);
      expect(large.size, const Size(684, 1080));
      expect(large.right, original.right);
      final small = scaledWindowBounds(large, 1.5, 0.75, work);
      expect(small.size, const Size(342, 540));
      expect(small.right, original.right);
      expect(scaledWindowBounds(small, 0.75, 1, work), original);
    },
  );
  test('large windows remain within the current monitor work area', () {
    const work = Rect.fromLTWH(-1280, 0, 1280, 720);
    final large = scaledWindowBounds(
      const Rect.fromLTWH(-470, 40, 456, 720),
      1,
      1.5,
      work,
    );
    expect(work.contains(large.topLeft), isTrue);
    expect(work.contains(large.bottomRight), isTrue);
    expect(large.height, 696);
  });

  test('native resize lowers minimum dimensions when switching from large to small', () async {
    const window = MethodChannel('window_manager');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var bounds = const Rect.fromLTWH(800, 24, 684, 1080);
    final calls = <MethodCall>[];
    var workHeight = 1800.0;
    messenger.setMockMethodCallHandler(window, (call) async {
      calls.add(call);
      if (call.method == 'getBounds') {
        return {
          'x': bounds.left,
          'y': bounds.top,
          'width': bounds.width,
          'height': bounds.height,
        };
      }
      if (call.method == 'setBounds') {
        final data = call.arguments as Map;
        bounds = Rect.fromLTWH(
          data['x'] as double,
          data['y'] as double,
          data['width'] as double,
          data['height'] as double,
        );
      }
      return null;
    });
    messenger.setMockMethodCallHandler(DesktopWindowSurface.channel, (
      call,
    ) async {
      if (call.method == 'workArea') {
        return {'left': 0.0, 'top': 0.0, 'width': 2000.0, 'height': workHeight};
      }
      calls.add(call);
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(window, null);
      messenger.setMockMethodCallHandler(DesktopWindowSurface.channel, null);
    });
    final surface = DesktopWindowSurface()..scale = 1.5;
    await surface.resize(0.75);
    expect(bounds.size, const Size(342, 540));
    final minimum =
        calls.firstWhere((call) => call.method == 'setMinimumSize').arguments
            as Map;
    expect(minimum['width'], 297);
    expect(minimum['height'], 375);
    expect(surface.scale, 0.75);
    expect(calls.last.method, 'shape');
    workHeight = 800;
    await surface.resize(1.5);
    expect(bounds.height, 776);
    await surface.resize(0.75);
    expect(
      bounds.size,
      const Size(342, 540),
    ); // Clipping must not shrink the remembered base size.
    final observer = WindowSurfaceObserver(surface);
    final route = MaterialPageRoute<void>(builder: (_) => const SizedBox());
    observer.didPush(route, null);
    await Future<void>.delayed(Duration.zero);
    expect(surface.notesVisible, false);
    expect((calls.last.arguments as Map)['notesVisible'], false);
  });
}
