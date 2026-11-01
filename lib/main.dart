import 'package:flutter/material.dart';

import 'update/app_updater.dart';
import 'update/update_dialog.dart';

/// Versión compilada (--dart-define=APP_VERSION); el número que se ve es el del APK instalado si el canal responde.
const buildVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

void main() => runApp(ZflUpdateApp(updater: AppUpdater()));

class ZflUpdateApp extends StatelessWidget {
  final AppUpdater updater;
  const ZflUpdateApp({super.key, required this.updater});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ZFL Update',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: zflYellow, useMaterial3: true),
    home: HomePage(updater: updater),
  );
}

class HomePage extends StatefulWidget {
  final AppUpdater updater;
  const HomePage({super.key, required this.updater});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final AppLifecycleListener _life = AppLifecycleListener(onResume: widget.updater.onResumed);

  @override
  void initState() {
    super.initState();
    _life;
    _check();
  }

  Future<void> _check() async {
    await widget.updater.check();
    if (mounted && widget.updater.state == UpdateState.available) await UpdateDialog.show(context, widget.updater);
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ListenableBuilder(
        listenable: widget.updater,
        builder: (context, _) => Text(
          widget.updater.current?.versionName ?? buildVersion,
          key: const ValueKey('version'),
          style: const TextStyle(fontFamily: 'Roboto', fontSize: 96, fontWeight: FontWeight.w800, color: zflInk),
        ),
      ),
    ),
  );
}
