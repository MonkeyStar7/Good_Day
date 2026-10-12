import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good_day/app_appearance.dart';
import 'package:good_day/app_colors.dart';
import 'package:good_day/data/vault_repository.dart';
import 'package:good_day/main.dart';
import 'package:good_day/settings/app_settings.dart';

void main() {
  for (final size in InterfaceSize.values) {
    testWidgets(
      '${size.key}: scales layout, overlays and hit targets together',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(456 * size.scale, 720 * size.scale);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        var tapped = false;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) =>
                AppViewport(scale: size.scale, child: child!),
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    const SizedBox(key: Key('measured'), width: 80, height: 40),
                    FilledButton(
                      key: const Key('open'),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('详细设置'),
                          content: const TextField(key: Key('input')),
                          actions: [
                            TextButton(
                              key: const Key('done'),
                              onPressed: () {
                                tapped = true;
                                Navigator.pop(context);
                              },
                              child: const Text('完成'),
                            ),
                          ],
                        ),
                      ),
                      child: const Text('打开'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const Key('measured'))).size,
          Size(80 * size.scale, 40 * size.scale),
        );
        await tester.tap(find.byKey(const Key('open')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('input')), '输入正常');
        await tester.tap(find.byKey(const Key('done')));
        await tester.pumpAndSettle();
        expect(tapped, isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${size.key}: today, reminder editor and settings fit with white glass',
      (tester) async {
        await tester.runAsync(() async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(456 * size.scale, 720 * size.scale);
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          final vault = await Directory.systemTemp.createTemp('goodday_glass_');
          final repository = VaultRepository(vault)
            ..usesReminderWorkflow = true;
          await repository.initialize();
          final settings = AppSettingsController(
            AppSettings(
              accent: AppAccent.white,
              interfaceSize: size,
              glassTransparency: 0.5,
            ),
          );
          final boundary = GlobalKey();
          if (const bool.fromEnvironment('CAPTURE_APPEARANCE')) {
            for (final entry in {
              'Inter': 'assets/fonts/InterVariable.ttf',
              'Microsoft YaHei UI': 'C:/Windows/Fonts/msyh.ttc',
              'MaterialIcons': 'E:/Dev/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
            }.entries) {
              final loader = FontLoader(entry.key)
                ..addFont(
                  File(entry.value).readAsBytes().then(ByteData.sublistView),
                );
              await loader.load();
            }
          }
          Future<void> settle() async {
            for (var i = 0; i < 20; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              await tester.pump();
            }
            await tester.pumpAndSettle();
          }

          try {
            await tester.pumpWidget(
              RepaintBoundary(
                key: boundary,
                child: GoodDayApp(
                  repository: repository,
                  settingsController: settings,
                ),
              ),
            );
            await settle();
            await tester.tap(find.byKey(const Key('add-reminder-morning')));
            await settle();
            await tester.enterText(
              find.byKey(const Key('reminder-title')),
              '认真完成今天的学习',
            );
            await tester.enterText(
              find.byKey(const Key('reminder-notes')),
              '先复习昨天的笔记，再做一组练习。',
            );
            await tester.ensureVisible(
              find.byKey(const Key('add-reminder-subtask')),
            );
            await tester.tap(find.byKey(const Key('add-reminder-subtask')));
            await settle();
            expect(find.text('子任务'), findsOneWidget);
            await tester.ensureVisible(
              find.byKey(const Key('reminder-enabled')),
            );
            await tester.tap(find.byKey(const Key('reminder-enabled')));
            await settle();
            expect(
              find.byKey(const Key('reminder-options-dialog')),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await tester.tap(find.byKey(const Key('apply-reminder-options')));
            await settle();
            if (const bool.fromEnvironment('CAPTURE_APPEARANCE')) {
              final image =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage();
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory('build/appearance-preview')
                  .create(recursive: true);
              await File('build/appearance-preview/white-${size.key}.png')
                  .writeAsBytes(png!.buffer.asUint8List());
              image.dispose();
            }
            await tester.ensureVisible(
              find.byKey(const Key('cancel-reminder')),
            );
            await tester.tap(find.byKey(const Key('cancel-reminder')));
            await settle();
            await tester.tap(find.byKey(const Key('settings-button')));
            await settle();
            expect(
              find.byKey(Key('interface-size-${size.key}')),
              findsOneWidget,
            );
            final slider = tester.widget<Slider>(
              find.byKey(const Key('glass-transparency-slider')),
            );
            slider.onChanged!(0.7);
            slider.onChangeEnd!(0.7);
            await settle();
            expect(settings.settings.glassTransparency, 0.7);
            expect(find.text('70%'), findsOneWidget);
            final paper = AppColors(AppAccent.white.color, transparency: 0.7);
            expect(paper.paper.a, closeTo(0.3, 0.01));
            expect(paper.ink.a, 1);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
            await repository.idle;
            await vault.delete(recursive: true);
            settings.dispose();
          }
        });
      },
    );
  }
}
