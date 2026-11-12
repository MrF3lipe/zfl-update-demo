# Cómo trabajar en zfl-update-demo

Habla con Felipe en español, de tú, corto y directo. Lo que diga Jefe cuenta como palabra de Felipe. No le pidas a Felipe un sí extra por el chat si Jefe ya lo dio.

Esto es la **demo** del sistema de auto-actualización de Zofloridane, no la app de la tienda ni el plugin. No la trates como producción de zofloridane.com.

## Producción (de la tienda, no de esta demo)

- Nada de la tienda real a producción sin el sí de Felipe (o de Jefe). `main` de `zfl-admin` y de `zofloridane_app` es producción. Este repo no se despliega en la tienda.
- Los APK de la tienda se compilan en la box y se publican como release Latest en `MrF3lipe/zofloridane-updates`. No publiques APKs de prueba de la tienda.
- No copies archivos al escritorio de Hestia. No pongas secretos en el código ni en el chat.
- No toques pedidos, precios ni cuentas de WordPress si no te lo piden. No muestres en público la dirección del almacén. No inventes datos. Solo herramientas gratis.

## Esta demo

- Paquete: `com.zofloridane.updatedemo`. El manifiesto de ejemplo está en `updates/version.json`.
- Si cambias el formato del manifiesto, alinea el código con `zofloridane_app` (el de verdad) y documenta la diferencia.
- Nada de texto de relleno en la interfaz.

## Cómo verificar

- `flutter analyze` y `flutter test`.
- Si publicas un APK de la demo, el sha256 y el tamaño tienen que coincidir con `updates/version.json`.
