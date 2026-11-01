#!/usr/bin/env python3
"""Genera version.json + parches bsdiff (copia de zfl-app-clientes 1aa1d42 tools/make_update.py para la demo).

Cambios: --app, --base-url por defecto la carpeta de la demo y --relative (url relativas a la carpeta del
version.json, que la app resuelve contra la URL del manifiesto). Además re-verifica cada parche escrito en disco.

  pip install bsdiff4   (gratis)
  python3 tools/make_update.py --new build/app/outputs/flutter-apk/app-release.apk \
      --version 2.10.24 --code 62 --old 61:/ruta/universal-61.apk [--old 60:/ruta/universal-60.apk] --out dist/update

Escribe en --out:  version.json, apk/universal-<code>.apk, patch/universal-<from>-<code>.bsdiff
Cada parche se comprueba aplicándolo (bspatch) antes de escribir version.json.
"""
import argparse, hashlib, json, os, shutil, sys

try:
    import bsdiff4
except ImportError:
    sys.exit('Falta bsdiff4: pip install bsdiff4')

BASE = 'https://felipe.eliasworks.uy/Apps/updates/zfl-update-demo'
APP = 'com.zofloridane.updatedemo'


def sha(b):
    return hashlib.sha256(b).hexdigest()


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--new', required=True)
    ap.add_argument('--version', required=True)
    ap.add_argument('--code', type=int, required=True)
    ap.add_argument('--old', action='append', default=[], help='versionCode:ruta.apk (se puede repetir)')
    ap.add_argument('--out', required=True)
    ap.add_argument('--variant', default='universal')
    ap.add_argument('--base-url', default=BASE)
    ap.add_argument('--app', default=APP)
    ap.add_argument('--relative', action='store_true', help='url relativas (apk/..., patch/...)')
    a = ap.parse_args(argv)
    pre = '' if a.relative else a.base_url.rstrip('/') + '/'

    new = open(a.new, 'rb').read()
    os.makedirs(os.path.join(a.out, 'apk'), exist_ok=True)
    os.makedirs(os.path.join(a.out, 'patch'), exist_ok=True)
    apk_name = f'{a.variant}-{a.code}.apk'
    shutil.copyfile(a.new, os.path.join(a.out, 'apk', apk_name))
    patches = []
    for spec in a.old:
        code_s, path = spec.split(':', 1)
        code = int(code_s)
        if code >= a.code:
            sys.exit(f'versionCode viejo {code} >= nuevo {a.code}')
        old = open(path, 'rb').read()
        p = bsdiff4.diff(old, new)
        if bsdiff4.patch(old, p) != new:
            sys.exit(f'el parche desde {code} no reconstruye el APK nuevo')
        name = f'{a.variant}-{code}-{a.code}.bsdiff'
        open(os.path.join(a.out, 'patch', name), 'wb').write(p)
        if sha(bsdiff4.patch(old, open(os.path.join(a.out, 'patch', name), 'rb').read())) != sha(new):
            sys.exit(f'el parche en disco desde {code} no da el sha256 del APK nuevo')
        patches.append({'fromVersionCode': code, 'fromSha256': sha(old), 'url': f'{pre}patch/{name}',
                        'sha256': sha(p), 'size': len(p)})
        print(f'parche {code}->{a.code}: {len(p)} bytes ({100 * len(p) / len(new):.1f} %)')
    manifest = {'format': 1, 'app': a.app, 'variants': {a.variant: {
        'version': a.version, 'versionCode': a.code,
        'apk': {'url': f'{pre}apk/{apk_name}', 'sha256': sha(new), 'size': len(new)},
        'patches': sorted(patches, key=lambda x: -x['fromVersionCode'])}}}
    with open(os.path.join(a.out, 'version.json'), 'w') as f:
        json.dump(manifest, f, indent=2)
        f.write('\n')
    print(os.path.join(a.out, 'version.json'))
    return manifest


if __name__ == '__main__':
    main()
