import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:updatedemo/update/app_updater.dart';
import 'package:updatedemo/update/update_dialog.dart';
import 'package:updatedemo/update/update_manifest.dart';

Future<void> loadRoboto() async {
  final l = FontLoader('Roboto');
  for (final f in ['Regular', 'Medium', 'Bold', 'Black']) {
    l.addFont(Future.value(ByteData.sublistView(File('test/fonts/Roboto-$f.ttf').readAsBytesSync())));
  }
  await l.load();
}

void main() {
  setUpAll(loadRoboto);

  AppUpdater updater(UpdateState s, double p) {
    final f = UpdateFile(url: 'https://x/apk', sha256: '0' * 64, size: 1);
    return AppUpdater(platform: const AndroidUpdatePlatform(forceAndroid: false))
      ..current = (path: '', versionCode: 1, versionName: '1.0.0')
      ..plan = UpdatePlan(UpdateVariant(version: '2.0.0', versionCode: 2, apk: f, patches: const []), null)
      ..state = s
      ..progress = p;
  }

  Future<void> shot(WidgetTester t, AppUpdater? u, String name) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: zflYellow, useMaterial3: true, fontFamily: 'Roboto'),
      home: Builder(builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (u != null) UpdateDialog.show(context, u);
        });
        return const Scaffold(
          body: Center(
            child: Text('1.0.0', style: TextStyle(fontFamily: 'Roboto', fontSize: 96, fontWeight: FontWeight.w800, color: zflInk)),
          ),
        );
      }),
    ));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  }

  testWidgets('golden pantalla', (t) => shot(t, null, 'pantalla'));
  testWidgets('golden pop-up', (t) => shot(t, updater(UpdateState.available, 0), 'popup'));
  testWidgets('golden progreso', (t) => shot(t, updater(UpdateState.downloading, 0.42), 'progreso'));
}
