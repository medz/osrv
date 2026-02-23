import 'dart:async';

import '../types/index.dart';

typedef PluginHook = FutureOr<void> Function(ServerPlugin plugin);
typedef LifecycleErrorHandler =
    FutureOr<void> Function(
      String stage,
      ServerPlugin plugin,
      Object error,
      StackTrace stackTrace,
    );

final class PluginLifecycleManager {
  PluginLifecycleManager({
    required Iterable<ServerPlugin> plugins,
    this.onError,
  }) : _plugins = List<ServerPlugin>.unmodifiable(plugins);

  final List<ServerPlugin> _plugins;
  final LifecycleErrorHandler? onError;

  List<ServerPlugin> get plugins => _plugins;

  Future<void> run(String stage, PluginHook hook) async {
    for (final plugin in _plugins) {
      try {
        await Future<void>.value(hook(plugin));
      } catch (error, stackTrace) {
        if (onError case final handler?) {
          await Future<void>.value(handler(stage, plugin, error, stackTrace));
          continue;
        }
        rethrow;
      }
    }
  }
}
