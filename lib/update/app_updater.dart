// Basado en zfl-app-clientes (1aa1d42) lib/update/app_updater.dart: version.json, parche bsdiff si el sha256 del
// APK instalado coincide con fromSha256 (si no, APK completo), verificación sha256 y PackageInstaller.
// Cambios de la demo: revisa siempre al abrir (sin intervalo de 6 h) y, si falta el permiso de instalar apps
// desconocidas, abre ese ajuste y continúa la instalación al volver ([onResumed]).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'bspatch.dart';
import 'update_manifest.dart';

enum UpdateState { idle, available, downloading, verifying, waitingPermission, installing, failed }

typedef Installed = ({String path, int versionCode, String versionName});

/// Lo que solo Android sabe: el APK instalado, el permiso y el instalador.
abstract class UpdatePlatform {
  Future<Installed?> installed();
  Future<bool> canInstall();
  Future<void> openInstallSettings();
  Future<bool> install(String apkPath);
}

class AndroidUpdatePlatform implements UpdatePlatform {
  static const channel = MethodChannel('zfl/update');
  final bool? forceAndroid; // tests: canal nativo falso fuera de Android
  const AndroidUpdatePlatform({this.forceAndroid});
  @override
  Future<Installed?> installed() async {
    if (!(forceAndroid ?? Platform.isAndroid)) return null;
    final m = await channel.invokeMapMethod<String, Object?>('installed');
    if (m == null) return null;
    return (path: '${m['path']}', versionCode: (m['versionCode'] as num).toInt(), versionName: '${m['versionName']}');
  }

  @override
  Future<bool> canInstall() async => await channel.invokeMethod<bool>('canInstall') ?? false;
  @override
  Future<void> openInstallSettings() => channel.invokeMethod('openInstallSettings');
  @override
  Future<bool> install(String apkPath) async => await channel.invokeMethod<bool>('install', {'path': apkPath}) ?? false;
}

Future<String> sha256OfFile(String path) async => (await sha256.bind(File(path).openRead()).first).toString();

class AppUpdater extends ChangeNotifier {
  static const manifestUrl = 'https://felipe.eliasworks.uy/Apps/updates/zfl-update-demo/version.json';
  static const appId = 'com.zofloridane.updatedemo';

  final http.Client client;
  final UpdatePlatform platform;
  final Future<String> Function() workDir;
  AppUpdater({http.Client? client, UpdatePlatform? platform, Future<String> Function()? workDir})
    : client = client ?? http.Client(),
      platform = platform ?? const AndroidUpdatePlatform(),
      workDir = workDir ?? (() async => '${await AndroidUpdatePlatform.channel.invokeMethod<String>('filesDir')}/updates');

  UpdateState state = UpdateState.idle;
  UpdatePlan? plan;
  Installed? current;
  double progress = 0;
  String? _readyApk;

  void _set(UpdateState s) {
    state = s;
    notifyListeners();
  }

  /// Siempre que se llama (al abrir la app). Nunca lanza: sin red o sin servidor, en silencio.
  Future<void> check() async {
    try {
      final inst = await platform.installed();
      if (inst == null) return;
      current = inst;
      notifyListeners();
      final res = await client.get(Uri.parse(manifestUrl)).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return;
      final m = UpdateManifest.parse(jsonDecode(utf8.decode(res.bodyBytes)), base: Uri.parse(manifestUrl));
      if (m == null) return;
      final quick = UpdatePlan.choose(m, app: appId, installedCode: inst.versionCode);
      if (quick == null) return;
      String? sha;
      if (quick.target.patches.any((p) => p.fromVersionCode == inst.versionCode)) sha = await sha256OfFile(inst.path);
      plan = UpdatePlan.choose(m, app: appId, installedCode: inst.versionCode, installedSha256: sha);
      if (plan != null) _set(UpdateState.available);
    } catch (_) {}
  }

  Future<File> _download(UpdateFile f, String to) async {
    final req = await client.send(http.Request('GET', Uri.parse(f.url)));
    if (req.statusCode != 200) throw HttpException('HTTP ${req.statusCode}');
    final out = File(to).openWrite();
    var got = 0;
    final total = f.size > 0 ? f.size : (req.contentLength ?? 0);
    await for (final c in req.stream) {
      out.add(c);
      got += c.length;
      if (total > 0) {
        progress = (got / total).clamp(0, 1).toDouble();
        notifyListeners();
      }
    }
    await out.close();
    if (await sha256OfFile(to) != f.sha256) {
      await File(to).delete();
      throw const FormatException('sha256');
    }
    return File(to);
  }

  /// Baja (parche o APK), verifica sha256 e instala (o pide el permiso y espera a [onResumed]).
  Future<void> run() async {
    final p = plan;
    final inst = current;
    if (p == null || inst == null) return;
    if (state == UpdateState.downloading || state == UpdateState.verifying || state == UpdateState.installing) return;
    progress = 0;
    _set(UpdateState.downloading);
    try {
      final dir = await workDir();
      await Directory(dir).create(recursive: true);
      final apk = '$dir/updatedemo-${p.target.versionCode}.apk';
      var ok = false;
      if (p.patch != null) {
        try {
          final patch = await _download(p.patch!, '$dir/p-${p.target.versionCode}.bsdiff');
          _set(UpdateState.verifying);
          final old = inst.path;
          await Isolate.run(() => bspatchFile(old, patch.path, apk));
          await patch.delete();
          ok = await sha256OfFile(apk) == p.target.apk.sha256;
        } catch (_) {
          ok = false;
        }
        if (!ok) {
          progress = 0;
          _set(UpdateState.downloading);
        }
      }
      if (!ok) {
        await _download(p.target.apk, apk);
        _set(UpdateState.verifying);
      }
      _readyApk = apk;
      await _install();
    } catch (_) {
      _set(UpdateState.failed);
    }
  }

  Future<void> _install() async {
    final apk = _readyApk;
    if (apk == null) return;
    if (!await platform.canInstall()) {
      _set(UpdateState.waitingPermission);
      await platform.openInstallSettings();
      return;
    }
    _set(UpdateState.installing);
    if (!await platform.install(apk)) _set(UpdateState.failed);
  }

  /// Al volver a la app (p. ej. desde el ajuste del permiso): si se concedió, sigue con la instalación.
  Future<void> onResumed() async {
    if (state != UpdateState.waitingPermission) return;
    try {
      if (await platform.canInstall()) await _install();
    } catch (_) {
      _set(UpdateState.failed);
    }
  }
}
