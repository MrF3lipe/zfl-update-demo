import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:updatedemo/main.dart';
import 'package:updatedemo/update/app_updater.dart';
import 'package:updatedemo/update/update_manifest.dart';

const base = 'https://felipe.eliasworks.uy/Apps/updates/zfl-update-demo/';
String shaOf(List<int> b) => sha256.convert(b).toString();

/// Canal nativo "zfl/update" falso: registra llamadas y simula el permiso.
class FakeChannel {
  final String apkPath;
  final int code;
  bool canInstall;
  final calls = <MethodCall>[];
  String? installedSha;
  FakeChannel(this.apkPath, {this.code = 1, this.canInstall = true});

  void attach() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      AndroidUpdatePlatform.channel,
      (c) async {
        calls.add(c);
        switch (c.method) {
          case 'installed':
            return {'path': apkPath, 'versionCode': code, 'versionName': '$code.0.0'};
          case 'canInstall':
            return canInstall;
          case 'openInstallSettings':
            return true;
          case 'install':
            installedSha = shaOf(File(c.arguments['path'] as String).readAsBytesSync());
            return true;
        }
        return null;
      },
    );
  }

  List<String> get methods => calls.map((c) => c.method).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final oldBytes = File('test/fixtures/old.bin').readAsBytesSync();
  final newBytes = File('test/fixtures/new.bin').readAsBytesSync();
  final patchBytes = File('test/fixtures/old-new.bsdiff').readAsBytesSync();
  late Directory tmp;
  late String oldPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('zfl-upd');
    oldPath = '${tmp.path}/installed.apk';
    File(oldPath).writeAsBytesSync(oldBytes);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, Object?> manifest({String? fromSha, String patchSha = '', int code = 2}) => {
    'format': 1,
    'app': 'com.zofloridane.updatedemo',
    'variants': {
      'universal': {
        'version': '$code.0.0',
        'versionCode': code,
        'apk': {'url': 'apk/universal-$code.apk', 'sha256': shaOf(newBytes), 'size': newBytes.length},
        'patches': [
          {
            'fromVersionCode': 1,
            'fromSha256': fromSha ?? shaOf(oldBytes),
            'url': 'patch/universal-1-$code.bsdiff',
            'sha256': patchSha.isEmpty ? shaOf(patchBytes) : patchSha,
            'size': patchBytes.length,
          },
        ],
      },
    },
  };

  ({AppUpdater u, List<String> urls}) make(Map<String, Object?> m) {
    final urls = <String>[];
    final client = MockClient((r) async {
      urls.add(r.url.toString());
      final u = r.url.toString();
      if (u == '${base}version.json') return http.Response(jsonEncode(m), 200);
      if (u.endsWith('.bsdiff')) return http.Response.bytes(patchBytes, 200);
      if (u.endsWith('.apk')) return http.Response.bytes(newBytes, 200);
      return http.Response('', 404);
    });
    final u = AppUpdater(
      client: client,
      platform: const AndroidUpdatePlatform(forceAndroid: true),
      workDir: () async => '${tmp.path}/updates',
    );
    return (u: u, urls: urls);
  }

  Future<void> openApp(WidgetTester t, AppUpdater u) async {
    await t.runAsync(() async {
      await t.pumpWidget(ZflUpdateApp(updater: u));
      for (var i = 0; i < 50 && u.state == UpdateState.idle; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await t.pumpAndSettle();
  }

  // Toca fuera del reloj falso: la descarga, el bspatch (Isolate) y el sha256 hacen E/S real.
  Future<void> tapReal(WidgetTester t, String text) => t.runAsync(() => t.tap(find.text(text)));

  Future<void> waitFor(WidgetTester t, bool Function() ok) async {
    await t.runAsync(() async {
      for (var i = 0; i < 200 && !ok(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await t.pump();
  }

  test('url relativas se resuelven contra la carpeta del version.json', () {
    final m = UpdateManifest.parse(manifest(), base: Uri.parse('${base}version.json'))!;
    expect(m.variants['universal']!.apk.url, '${base}apk/universal-2.apk');
    expect(m.variants['universal']!.patches.single.url, '${base}patch/universal-1-2.bsdiff');
  });

  testWidgets('pop-up: título, versión, Actualizar (#ffcc00/#111827) y Ahora no', (t) async {
    FakeChannel(oldPath).attach();
    final r = make(manifest());
    await openApp(t, r.u);
    expect(find.text('Actualización disponible'), findsOneWidget);
    expect(find.text('2.0.0'), findsOneWidget);
    expect(find.text('Ahora no'), findsOneWidget);
    final btn = t.widget<FilledButton>(find.byKey(const ValueKey('upd-go')));
    expect(btn.style!.backgroundColor!.resolve({}), const Color(0xFFFFCC00));
    expect(btn.style!.foregroundColor!.resolve({}), const Color(0xFF111827));
    expect(find.text('1.0.0'), findsOneWidget); // versión instalada, grande en la pantalla
    await t.tap(find.text('Ahora no'));
    await t.pumpAndSettle();
    expect(find.text('Actualización disponible'), findsNothing);
  });

  testWidgets('sin versión nueva no hay pop-up (siempre revisa version.json)', (t) async {
    FakeChannel(oldPath, code: 2).attach();
    final r = make(manifest());
    await openApp(t, r.u);
    await waitFor(t, () => r.urls.isNotEmpty);
    expect(r.urls, ['${base}version.json']);
    expect(find.text('Actualización disponible'), findsNothing);
  });

  testWidgets('Actualizar: parche (fromSha256 coincide) → sha256 exacto → PackageInstaller', (t) async {
    final ch = FakeChannel(oldPath)..attach();
    final r = make(manifest());
    await openApp(t, r.u);
    await tapReal(t, 'Actualizar');
    await waitFor(t, () => ch.installedSha != null);
    expect(r.urls.last, '${base}patch/universal-1-2.bsdiff');
    expect(r.urls.where((u) => u.endsWith('.apk')), isEmpty);
    expect(ch.installedSha, shaOf(newBytes));
    expect(r.u.state, UpdateState.installing);
  });

  testWidgets('fromSha256 distinto → APK completo', (t) async {
    final ch = FakeChannel(oldPath)..attach();
    final r = make(manifest(fromSha: 'a' * 64));
    await openApp(t, r.u);
    await tapReal(t, 'Actualizar');
    await waitFor(t, () => ch.installedSha != null);
    expect(r.urls.last, '${base}apk/universal-2.apk');
    expect(r.urls.where((u) => u.endsWith('.bsdiff')), isEmpty);
    expect(ch.installedSha, shaOf(newBytes));
  });

  testWidgets('parche con sha256 incorrecto → se descarta y baja el APK completo', (t) async {
    final ch = FakeChannel(oldPath)..attach();
    final r = make(manifest(patchSha: 'b' * 64));
    await openApp(t, r.u);
    await tapReal(t, 'Actualizar');
    await waitFor(t, () => ch.installedSha != null);
    expect(r.urls.skip(1), ['${base}patch/universal-1-2.bsdiff', '${base}apk/universal-2.apk']);
    expect(ch.installedSha, shaOf(newBytes));
  });

  testWidgets('sin permiso: abre el ajuste y al volver continúa e instala', (t) async {
    final ch = FakeChannel(oldPath, canInstall: false)..attach();
    final r = make(manifest());
    await openApp(t, r.u);
    await tapReal(t, 'Actualizar');
    await waitFor(t, () => r.u.state == UpdateState.waitingPermission);
    expect(ch.methods, contains('openInstallSettings'));
    expect(ch.methods, isNot(contains('install')));
    expect(find.byKey(const ValueKey('upd-progress')), findsOneWidget);
    // Vuelve del ajuste con el permiso concedido.
    ch.canInstall = true;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await waitFor(t, () => ch.installedSha != null);
    expect(ch.installedSha, shaOf(newBytes));
    expect(ch.methods.where((m) => m == 'openInstallSettings').length, 1);
  });

  testWidgets('descarga fallida (404) → estado failed y vuelve a ofrecer Actualizar', (t) async {
    FakeChannel(oldPath).attach();
    final m = manifest(fromSha: 'a' * 64);
    ((m['variants'] as Map)['universal'] as Map)['apk'] = {'url': 'apk/nope.bin', 'sha256': shaOf(newBytes), 'size': 1};
    final r = make(m);
    await openApp(t, r.u);
    await tapReal(t, 'Actualizar');
    await waitFor(t, () => r.u.state == UpdateState.failed);
    expect(find.text('Actualizar'), findsOneWidget);
  });
}
