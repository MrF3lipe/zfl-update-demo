// Verifica las entregas reales (/workspace/entregas/update-demo) con el bspatch de la app: cada parche aplicado
// sobre el APK de origen da exactamente el sha256 del APK nuevo publicado en version.json. Se salta si no existen.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:updatedemo/update/app_updater.dart';
import 'package:updatedemo/update/bspatch.dart';
import 'package:updatedemo/update/update_manifest.dart';

const root = '/workspace/entregas/update-demo';
final apks = {1: '$root/v1/zfl-update-1.0.0+1.apk', 2: '$root/v2/apk/universal-2.apk', 3: '$root/v3/apk/universal-3.apk'};
// version.json con URLs absolutas de GitHub Releases; los archivos locales siguen en apk/ y patch/.

void main() {
  final skip = !File('$root/v3/version.json').existsSync();
  for (final v in [2, 3]) {
    test('v$v: parches → sha256 exacto y plan correcto', () async {
      final base = Uri.parse(AppUpdater.manifestUrl);
      final m = UpdateManifest.parse(jsonDecode(File('$root/v$v/version.json').readAsStringSync()), base: base)!;
      final t = m.variants['universal']!;
      expect(t.versionCode, v);
      expect(t.apk.url, 'https://github.com/MrF3lipe/zfl-update-demo/releases/download/v$v.0.0/universal-$v.apk');
      expect(await sha256OfFile('$root/v$v/apk/universal-$v.apk'), t.apk.sha256);
      expect(File('$root/v$v/apk/universal-$v.apk').lengthSync(), t.apk.size);
      expect(t.patches.map((p) => p.fromVersionCode).toSet(), {for (var f = 1; f < v; f++) f});
      final tmp = Directory.systemTemp.createTempSync('zfl-real');
      for (final p in t.patches) {
        final name = p.url.split('/').last;
        final patch = '$root/v$v/patch/$name';
        expect(await sha256OfFile(patch), p.sha256);
        expect(File(patch).lengthSync(), p.size);
        final from = apks[p.fromVersionCode]!;
        expect(await sha256OfFile(from), p.fromSha256);
        final out = '${tmp.path}/out-${p.fromVersionCode}.apk';
        await bspatchFile(from, patch, out);
        expect(await sha256OfFile(out), t.apk.sha256, reason: name);
        final plan = UpdatePlan.choose(m, app: AppUpdater.appId, installedCode: p.fromVersionCode, installedSha256: p.fromSha256)!;
        expect(plan.patch?.url, p.url);
        // sha del instalado distinto → APK completo
        expect(UpdatePlan.choose(m, app: AppUpdater.appId, installedCode: p.fromVersionCode, installedSha256: 'f' * 64)!.patch, isNull);
      }
      expect(UpdatePlan.choose(m, app: AppUpdater.appId, installedCode: v), isNull);
      tmp.deleteSync(recursive: true);
    }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
  }
}
