import 'dart:async';

import 'package:ht/ht.dart';

import 'core/config.dart';
import 'core/dispatcher.dart';
import 'core/lifecycle.dart';
import 'request.dart';
import 'runtime/server_transport.dart';
import 'types/index.dart';

final class Server implements ServerHandle {
  Server({
    required FetchHandler fetch,
    String? hostname,
    int? port,
    bool reusePort = false,
    bool silent = false,
    HTTPProtocol? protocol,
    TLSOptions? tls,
    bool? http2,
    ErrorHandler? error,
    Iterable<Middleware> middleware = const <Middleware>[],
    Iterable<ServerPlugin> plugins = const <ServerPlugin>[],
    bool manual = false,
    Map<String, String>? env,
  }) : this.fromOptions(
         ServerOptions(
           fetch: fetch,
           hostname: hostname,
           port: port,
           reusePort: reusePort,
           silent: silent,
           protocol: protocol,
           tls: tls,
           http2: http2,
           error: error,
           middleware: middleware,
           plugins: plugins,
           manual: manual,
           env: env,
         ),
       );

  Server.fromOptions(this.options) : config = ServerConfig.resolve(options) {
    _lifecycle = PluginLifecycleManager(
      plugins: config.plugins,
      onError: _handleLifecycleError,
    );

    _dispatcher = RequestDispatcher(
      server: this,
      fetch: options.fetch,
      error: options.error,
      middleware: config.middleware,
      plugins: config.plugins,
    );

    _transport = createServerTransport(
      config: config,
      dispatch: _dispatcher.dispatch,
      trackBackgroundTask: _trackBackgroundTask,
    );
  }

  @override
  final ServerOptions options;

  final ServerConfig config;

  late final PluginLifecycleManager _lifecycle;
  late final RequestDispatcher _dispatcher;
  late final ServerTransport _transport;

  final Set<Future<Object?>> _backgroundTasks = <Future<Object?>>{};

  bool _started = false;
  bool _closed = false;

  @override
  Runtime get runtime => _transport.runtime;

  @override
  Uri get url => _started ? _transport.url : config.defaultUrl();

  @override
  String get addr {
    final host = _started ? _transport.hostname : config.hostname;
    final port = _started ? _transport.port : config.port;
    final normalizedHost = host.contains(':') ? '[$host]' : host;
    return '$normalizedHost:$port';
  }

  @override
  int get port => _started ? _transport.port : config.port;

  Future<Response> fetch(ServerRequest request) {
    return _dispatcher.dispatch(request);
  }

  Future<Server> serve() async {
    if (_closed) {
      throw StateError('Server is already closed.');
    }

    if (_started) {
      return this;
    }

    _started = true;
    try {
      await _lifecycle.run('register', (plugin) => plugin.onRegister(this));
      await _lifecycle.run(
        'beforeServe',
        (plugin) => plugin.onBeforeServe(this),
      );

      await _transport.serve();
      await _transport.ready();

      await _lifecycle.run('afterServe', (plugin) => plugin.onAfterServe(this));
      return this;
    } catch (_) {
      _started = false;
      rethrow;
    }
  }

  Future<Server> ready() async {
    if (!_started) {
      if (config.manual) {
        return this;
      }
      await serve();
      return this;
    }

    await _transport.ready();
    return this;
  }

  Future<void> close([bool? closeActiveConnections]) async {
    if (_closed) {
      return;
    }

    _closed = true;
    final force = closeActiveConnections ?? false;

    if (_started) {
      await _lifecycle.run(
        'beforeClose',
        (plugin) => plugin.onBeforeClose(this),
      );

      await _transport.close(force: force);

      if (_backgroundTasks.isNotEmpty) {
        await Future.wait(_backgroundTasks, eagerError: false);
      }

      await _lifecycle.run('afterClose', (plugin) => plugin.onAfterClose(this));
      _started = false;
    }
  }

  void _trackBackgroundTask(Future<Object?> task) {
    _backgroundTasks.add(task);
    task.whenComplete(() {
      _backgroundTasks.remove(task);
    });
  }

  Future<void> _handleLifecycleError(
    String stage,
    ServerPlugin plugin,
    Object error,
    StackTrace stackTrace,
  ) async {
    final wrapped = StateError(
      'Plugin lifecycle failed at "$stage" (${plugin.runtimeType}): $error',
    );
    Zone.current.handleUncaughtError(wrapped, stackTrace);
    throw wrapped;
  }
}
