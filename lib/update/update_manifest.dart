// Copiado de zfl-app-clientes (1aa1d42) lib/update/update_manifest.dart. Formato de version.json (format 1).
// Único cambio: las url pueden ser relativas a la carpeta del version.json (se resuelven con [base]).

class UpdateFile {
  final String url;
  final String sha256;
  final int size;
  const UpdateFile({required this.url, required this.sha256, required this.size});

  static UpdateFile? fromJson(Object? j, [Uri? base]) {
    if (j is! Map) return null;
    final raw = j['url'], sha = j['sha256'];
    final url = raw is String && base != null ? base.resolve(raw).toString() : raw;
    if (url is! String || sha is! String || !url.startsWith('https://') || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha.toLowerCase())) {
      return null;
    }
    return UpdateFile(url: url, sha256: sha.toLowerCase(), size: (j['size'] as num?)?.toInt() ?? 0);
  }
}

class UpdatePatch extends UpdateFile {
  final int fromVersionCode;
  final String fromSha256;
  const UpdatePatch({
    required super.url,
    required super.sha256,
    required super.size,
    required this.fromVersionCode,
    required this.fromSha256,
  });

  static UpdatePatch? parse(Object? j, [Uri? base]) {
    final f = UpdateFile.fromJson(j, base);
    if (f == null || j is! Map) return null;
    final from = (j['fromVersionCode'] as num?)?.toInt();
    final fromSha = (j['fromSha256'] as String?)?.toLowerCase();
    if (from == null || fromSha == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(fromSha)) return null;
    return UpdatePatch(url: f.url, sha256: f.sha256, size: f.size, fromVersionCode: from, fromSha256: fromSha);
  }
}

class UpdateVariant {
  final String version;
  final int versionCode;
  final UpdateFile apk;
  final List<UpdatePatch> patches;
  const UpdateVariant({required this.version, required this.versionCode, required this.apk, required this.patches});
}

class UpdateManifest {
  final String app;
  final Map<String, UpdateVariant> variants;
  const UpdateManifest(this.app, this.variants);

  static UpdateManifest? parse(Object? j, {Uri? base}) {
    if (j is! Map || j['format'] != 1 || j['variants'] is! Map) return null;
    final out = <String, UpdateVariant>{};
    (j['variants'] as Map).forEach((k, v) {
      if (v is! Map) return;
      final apk = UpdateFile.fromJson(v['apk'], base);
      final code = (v['versionCode'] as num?)?.toInt();
      if (apk == null || code == null) return;
      final patches = <UpdatePatch>[
        for (final p in (v['patches'] is List ? v['patches'] as List : const [])) ?UpdatePatch.parse(p, base),
      ];
      out['$k'] = UpdateVariant(version: '${v['version'] ?? ''}', versionCode: code, apk: apk, patches: patches);
    });
    return out.isEmpty ? null : UpdateManifest('${j['app'] ?? ''}', out);
  }
}

/// Qué bajar: parche si existe uno desde la versión instalada y el APK instalado es exactamente ese
/// (mismo sha256); si no, el APK completo. Null = no hay nada nuevo.
class UpdatePlan {
  final UpdateVariant target;
  final UpdatePatch? patch;
  const UpdatePlan(this.target, this.patch);
  UpdateFile get download => patch ?? target.apk;

  static UpdatePlan? choose(
    UpdateManifest m, {
    required String app,
    required int installedCode,
    String? installedSha256,
    String variant = 'universal',
  }) {
    if (m.app.isNotEmpty && m.app != app) return null;
    final v = m.variants[variant];
    if (v == null || v.versionCode <= installedCode) return null;
    final sha = installedSha256?.toLowerCase();
    for (final p in v.patches) {
      if (p.fromVersionCode == installedCode && sha != null && p.fromSha256 == sha) return UpdatePlan(v, p);
    }
    return UpdatePlan(v, null);
  }
}
