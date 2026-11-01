import 'package:flutter/material.dart';

import 'app_updater.dart';

const zflYellow = Color(0xFFFFCC00);
const zflInk = Color(0xFF111827);

/// Pop-up «Actualización disponible»: versión + «Actualizar» / «Ahora no»; mientras baja, el progreso.
class UpdateDialog extends StatelessWidget {
  final AppUpdater updater;
  const UpdateDialog({super.key, required this.updater});

  static Future<void> show(BuildContext context, AppUpdater u) =>
      showDialog(context: context, barrierDismissible: false, builder: (_) => UpdateDialog(updater: u));

  @override
  Widget build(BuildContext context) {
    final u = updater;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final busy = switch (u.state) {
          UpdateState.downloading || UpdateState.verifying || UpdateState.installing || UpdateState.waitingPermission => true,
          _ => false,
        };
        final version = u.plan?.target.version ?? '';
        return PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: const Text('Actualización disponible'),
            content: busy
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(version, key: const ValueKey('upd-version'), style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        key: const ValueKey('upd-progress'),
                        value: u.state == UpdateState.downloading ? u.progress : null,
                        color: zflYellow,
                        backgroundColor: const Color(0xFFE5E7EB),
                        minHeight: 8,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        u.state == UpdateState.downloading ? '${(u.progress * 100).round()} %' : '100 %',
                        key: const ValueKey('upd-percent'),
                        textAlign: TextAlign.end,
                      ),
                    ],
                  )
                : Text(version, key: const ValueKey('upd-version'), style: Theme.of(context).textTheme.titleLarge),
            actions: busy
                ? const []
                : [
                    TextButton(
                      key: const ValueKey('upd-later'),
                      style: TextButton.styleFrom(foregroundColor: zflInk),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Ahora no'),
                    ),
                    FilledButton(
                      key: const ValueKey('upd-go'),
                      style: FilledButton.styleFrom(
                        backgroundColor: zflYellow,
                        foregroundColor: zflInk,
                        textStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      onPressed: u.run,
                      child: const Text('Actualizar'),
                    ),
                  ],
          ),
        );
      },
    );
  }
}
