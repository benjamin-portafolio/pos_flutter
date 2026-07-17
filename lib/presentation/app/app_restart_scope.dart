import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/config/app_config.dart';
import '../../core/di/injection.dart';

typedef AppDependencyRestarter =
    Future<DependencyBootstrap> Function(AppConfig previousConfig);

class AppRestartScope extends StatefulWidget {
  const AppRestartScope({
    super.key,
    required this.initialConfig,
    required this.builder,
    this.restartDependencies = _restartDependencies,
  });

  final AppConfig initialConfig;
  final Widget Function(AppConfig config) builder;
  final AppDependencyRestarter restartDependencies;

  static Future<void> restart(BuildContext context) {
    final state = context.findAncestorStateOfType<_AppRestartScopeState>();
    if (state == null) {
      throw StateError('No se encontro AppRestartScope en el arbol.');
    }

    return state.restart();
  }

  @override
  State<AppRestartScope> createState() => _AppRestartScopeState();
}

class _AppRestartScopeState extends State<AppRestartScope> {
  late AppConfig _config;
  var _appKey = UniqueKey();
  var _isRestarting = false;
  Object? _restartError;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
  }

  @override
  void dispose() {
    unawaited(stopConfiguredRuntimeServices(_config));
    super.dispose();
  }

  Future<void> restart() async {
    if (_isRestarting) return;

    setState(() {
      _isRestarting = true;
      _restartError = null;
    });

    try {
      final bootstrap = await widget.restartDependencies(_config);
      if (!mounted) return;

      setState(() {
        _config = bootstrap.appConfig;
        _appKey = UniqueKey();
        _isRestarting = false;
      });
    } catch (error) {
      if (!mounted) rethrow;

      setState(() {
        _restartError = error;
        _isRestarting = false;
      });
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isRestarting) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final restartError = _restartError;
    if (restartError != null) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(child: Text('No se pudo reabrir la base local.')),
        ),
      );
    }

    return KeyedSubtree(key: _appKey, child: widget.builder(_config));
  }
}

Future<DependencyBootstrap> _restartDependencies(AppConfig previousConfig) {
  return restartDependencyInjection(previousConfig: previousConfig);
}
