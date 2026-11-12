# zfl-update-demo

Demo Flutter del sistema de auto-actualización de la app Zofloridane (parche bsdiff o APK completo). No es la tienda ni el panel.

La tienda de verdad es [zofloridane.com](https://zofloridane.com): la gente que vive fuera le compra a la familia en Cuba. El código de producción está en `MrF3lipe/zofloridane_app` (app), `MrF3lipe/zfl-admin` (plugin) y `MrF3lipe/zofloridane-updates` (manifiesto y APK reales).

## Estructura

| Ruta | Qué es |
|---|---|
| `lib/main.dart` | App mínima: muestra la versión y abre el diálogo de actualización |
| `lib/update/` | Cliente (`app_updater.dart`, `update_manifest.dart`, `bspatch.dart`, `update_dialog.dart`) |
| `tools/make_update.py` | Arma el manifiesto y los parches |
| `updates/version.json` | Manifiesto de ejemplo (`app`: `com.zofloridane.updatedemo`) |
| `test/` | Pruebas |
| `android/` | Proyecto Android |

`pubspec.yaml` tiene `1.0.0+1`. El manifiesto de ejemplo apunta a la versión **3.0.0**, versionCode **3**, con parches desde 1 y 2. La versión que ve la demo puede venir de `--dart-define=APP_VERSION`.

## Cómo compilar y probar

```
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Los releases de esta demo (si se publican) viven en este mismo repo, no en `zofloridane-updates`.

## Variables de entorno (solo nombres)

- `APP_VERSION` — `--dart-define`, versión de compilación si el canal aún no responde.

Este repo no debe llevar secretos de la tienda (keystore, Firebase, claves de socio). Esos nombres, en la app real, son `ZFL_KEY_PROPERTIES`, `ZFL_KEYSTORE_B64`, `ZFL_KEYSTORE_PASSWORD`, `ZFL_KEY_PASSWORD`, `ZFL_KEY_ALIAS`, `ZFL_GOOGLE_SERVICES_B64`, `ZFL_SITE`, `ZFL_FCM_SA_PATH`.

## Integraciones

Solo el esquema de `version.json` (format 1, variante `universal`, sha256, parches `fromVersionCode`). No habla con la Store API, ni con el panel, ni con `GET /wp-json/zfl/v1/socio/nomina`, ni con NIIMBOT.

## Reglas de negocio (contexto; no se implementan aquí)

- Ganancia de la tienda en USD, 100 % dueños: Michel 90 / Felipe 10.
- Empleados: 10 CUP por USD vendido, Yasniely 60 / Yani 20 / almacenero 20.
- Propinas: 50/50 y luego 90/10 y 60/20/20 dentro de cada grupo.
- Cuentas `vladimir`, `Luis Felipe` y `admin` = Felipe.
- Familias por peso: sin marca y por peso → familia; con marca o paquete de unidades iguales → suelto; con hueso ≠ deshuesado; fresco ≠ ahumado; congelado = fresco; jamón de pierna entero en familia; viandas sueltas.
