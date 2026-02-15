import 'dart:async';

import 'package:ht/ht.dart' show Response;

import 'exceptions.dart';
import 'request.dart';
import 'runtime/environment.dart';
import 'runtime/server_transport.dart';
import 'types.dart';

final class Server implements ServerHandle, ServerTransportHost {
  Server({
    required this.fetch,
    List<Middleware>? middleware,
    List<ServerPlugin>? plugins,
    this.error,
    int? port,
    String? hostname,
    ServerProtocol? protocol,
    this.reusePort = false,
    this.silent = false,
    this.gracefulShutdown = const GracefulShutdownOptions(),
    this.tls,
    this.trustProxy = false,
    ServerLogger? logger,
    this.securityLimits = const ServerSecurityLimits(),
    this.webSocketLimits = const WebSocketLimits(),
    this.node = const NodeOptions(<String, Object?>{}),
    this.bun = const BunOptions(<String, Object?>{}),
    this.deno = const DenoOptions(<String, Object?>{}),
    this.cloudflare = const CloudflareOptions(<String, Object?>{}),
    this.vercel = const VercelOptions(<String, Object?>{}),
    this.netlify = const NetlifyOptions(<String, Object?>{}),
    Map<String, String>? environment,
  }) : middleware = List<Middleware>.unmodifiable(middleware ?? const []),
       plugins = List<ServerPlugin>.unmodifiable(plugins ?? const []),
       logger = logger ?? const StdServerLogger(),
       _environment = Map<String, String>.unmodifiable(
         environment ?? readRuntimeEnvironment(),
       ),
       _resolvedPort = _resolvePort(
         port,
         environment ?? readRuntimeEnvironment(),
       ),
       _resolvedHostname = _resolveHostname(
         hostname,
         environment ?? readRuntimeEnvironment(),
       ),
       _resolvedProtocol =
           protocol ??
           ((tls?.isConfigured ?? false)
               ? ServerProtocol.https
               : ServerProtocol.http) {
    _transport = createServerTransport(this);
  }

  final FetchHandler fetch;
  final List<Middleware> middleware;
  final List<ServerPlugin> plugins;
  final ErrorHandler? error;
  @override
  final bool reusePort;
  @override
  final bool silent;
  @override
  final GracefulShutdownOptions gracefulShutdown;
  final TlsOptions? tls;
  @override
  final bool trustProxy;
  final ServerLogger logger;
  @override
  final ServerSecurityLimits securityLimits;
  @override
  final WebSocketLimits webSocketLimits;
  final NodeOptions node;
  final BunOptions bun;
  final DenoOptions deno;
  final CloudflareOptions cloudflare;
  final VercelOptions vercel;
  final NetlifyOptions netlify;

  final Map<String, String> _environment;
  final int _resolvedPort;
  final String _resolvedHostname;
  final ServerProtocol _resolvedProtocol;

  late final ServerTransport _transport;

  final Set<Future<Object?>> _backgroundTasks = <Future<Object?>>{};

  bool _registered = false;
  bool _serving = false;
  bool _emittingPluginError = false;

  @override
  bool get isServing => _serving;

  @override
  String? get url => _transport.url;

  String get runtime => _transport.runtimeName;

  @override
  ServerCapabilities get capabilities => _transport.capabilities;

  int get port => _resolvedPort;

  String get hostname => _resolvedHostname;

  ServerProtocol get protocol => _resolvedProtocol;

  @override
  bool get isProduction {
    final env =
        (_environment['OSRV_ENV'] ??
                _environment['ENV'] ??
                _environment['NODE_ENV'] ??
                '')
            .toLowerCase();
    return env == 'prod' || env == 'production';
  }

  Future<Server> serve() async {
    await _ensureRegistered();

    try {
      await _runBeforeServe();
      await _transport.serve();
      _serving = true;
      await _runAfterServe();
      return this;
    } catch (error, stackTrace) {
      await _handleLifecycleError(
        error,
        stackTrace,
        stage: ErrorStage.transport,
      );
      rethrow;
    }
  }

  Future<void> close({bool force = false}) async {
    try {
      await _runBeforeClose(force: force);
      await _transport.close(force: force);
      if (!force) {
        await _waitForBackgroundTasks();
      }
      _serving = false;
      await _runAfterClose(force: force);
    } catch (error, stackTrace) {
      await _handleLifecycleError(
        error,
        stackTrace,
        stage: ErrorStage.afterClose,
      );
      rethrow;
    }
  }

  Future<Response> _runHandler(ServerRequest request) async {
    Future<Response> runAt(int index) {
      if (index >= middleware.length) {
        return Future<Response>.value(fetch(request));
      }

      final current = middleware[index];
      return current(request, () => runAt(index + 1));
    }

    return runAt(0);
  }

  @override
  Future<Response> dispatch(ServerRequest request) async {
    try {
      return await _runHandler(request);
    } catch (error, stackTrace) {
      await _emitPluginError(
        stage: ErrorStage.request,
        error: error,
        stackTrace: stackTrace,
        request: request,
      );

      final handler = this.error;
      if (handler != null) {
        return Future<Response>.value(handler(error, stackTrace, request));
      }

      return _defaultErrorResponse(error, stackTrace);
    }
  }

  Response _defaultErrorResponse(Object error, StackTrace stackTrace) {
    if (error is RequestLimitExceeded) {
      return Response.json(<String, Object>{
        'ok': false,
        'error': 'Request body too large',
        'maxBytes': error.maxBytes,
        'actualBytes': error.actualBytes,
      }, status: 413);
    }

    if (isProduction) {
      return Response.json(const <String, Object>{
        'ok': false,
        'error': 'Internal Server Error',
      }, status: 500);
    }

    return Response.json(<String, Object>{
      'ok': false,
      'error': 'Internal Server Error',
      'details': error.toString(),
      'stack': stackTrace.toString(),
    }, status: 500);
  }

  Future<void> _ensureRegistered() async {
    if (_registered) {
      return;
    }

    for (final plugin in plugins) {
      try {
        await plugin.onRegister(RegisterPluginContext(server: this));
      } catch (error, stackTrace) {
        await _handleLifecycleError(
          error,
          stackTrace,
          stage: ErrorStage.register,
        );
        rethrow;
      }
    }

    _registered = true;
  }

  Future<void> _runBeforeServe() async {
    for (final plugin in plugins) {
      try {
        await plugin.onBeforeServe(BeforeServePluginContext(server: this));
      } catch (error, stackTrace) {
        await _handleLifecycleError(
          error,
          stackTrace,
          stage: ErrorStage.beforeServe,
        );
        rethrow;
      }
    }
  }

  Future<void> _runAfterServe() async {
    for (final plugin in plugins) {
      try {
        await plugin.onAfterServe(AfterServePluginContext(server: this));
      } catch (error, stackTrace) {
        await _handleLifecycleError(
          error,
          stackTrace,
          stage: ErrorStage.afterServe,
        );
        rethrow;
      }
    }
  }

  Future<void> _runBeforeClose({required bool force}) async {
    for (final plugin in plugins) {
      try {
        await plugin.onBeforeClose(
          BeforeClosePluginContext(server: this, force: force),
        );
      } catch (error, stackTrace) {
        await _handleLifecycleError(
          error,
          stackTrace,
          stage: ErrorStage.beforeClose,
        );
        rethrow;
      }
    }
  }

  Future<void> _runAfterClose({required bool force}) async {
    for (final plugin in plugins) {
      try {
        await plugin.onAfterClose(
          AfterClosePluginContext(server: this, force: force),
        );
      } catch (error, stackTrace) {
        await _handleLifecycleError(
          error,
          stackTrace,
          stage: ErrorStage.afterClose,
        );
        rethrow;
      }
    }
  }

  Future<void> _handleLifecycleError(
    Object error,
    StackTrace stackTrace, {
    required ErrorStage stage,
    ServerRequest? request,
  }) async {
    await _emitPluginError(
      stage: stage,
      error: error,
      stackTrace: stackTrace,
      request: request,
    );

    final handler = this.error;
    if (handler != null) {
      try {
        await Future<Response>.value(handler(error, stackTrace, request));
      } catch (handlerError, handlerStackTrace) {
        logError(
          'Lifecycle error handler failed',
          handlerError,
          handlerStackTrace,
        );
      }
    }
  }

  Future<void> _emitPluginError({
    required ErrorStage stage,
    required Object error,
    required StackTrace stackTrace,
    ServerRequest? request,
  }) async {
    if (_emittingPluginError) {
      logError('Nested plugin error', error, stackTrace);
      return;
    }

    _emittingPluginError = true;
    try {
      for (final plugin in plugins) {
        try {
          await plugin.onError(
            ErrorPluginContext(
              server: this,
              stage: stage,
              error: error,
              stackTrace: stackTrace,
              request: request,
            ),
          );
        } catch (pluginError, pluginStackTrace) {
          logError('Plugin onError hook failed', pluginError, pluginStackTrace);
        }
      }
    } finally {
      _emittingPluginError = false;
    }
  }

  Future<void> _waitForBackgroundTasks() async {
    if (_backgroundTasks.isEmpty) {
      return;
    }

    final pending = _backgroundTasks.toList(growable: false);
    try {
      await Future.wait<Object?>(
        pending,
        eagerError: false,
      ).timeout(gracefulShutdown.gracefulTimeout);
    } on TimeoutException {
      logWarn('Background tasks exceeded graceful shutdown timeout.');
    }
  }

  @override
  int get resolvedPort => _resolvedPort;

  @override
  String get resolvedHostname => _resolvedHostname;

  @override
  ServerProtocol get resolvedProtocol => _resolvedProtocol;

  @override
  TlsOptions? get tlsOptions => tls;

  @override
  void trackBackgroundTask(Future<Object?> task) {
    _backgroundTasks.add(task);
    task.whenComplete(() {
      _backgroundTasks.remove(task);
    });
  }

  @override
  void logInfo(String message) {
    if (!silent) {
      logger.info(message);
    }
  }

  @override
  void logWarn(String message) {
    if (!silent) {
      logger.warn(message);
    }
  }

  @override
  void logError(String message, [Object? error, StackTrace? stackTrace]) {
    logger.error(message, error, stackTrace);
  }

  static int _resolvePort(int? configured, Map<String, String> environment) {
    if (configured != null) {
      return configured;
    }

    final fromPort = int.tryParse(environment['PORT'] ?? '');
    if (fromPort != null) {
      return fromPort;
    }

    final fromNamespaced = int.tryParse(environment['OSRV_PORT'] ?? '');
    if (fromNamespaced != null) {
      return fromNamespaced;
    }

    return 3000;
  }

  static String _resolveHostname(
    String? configured,
    Map<String, String> environment,
  ) {
    if (configured != null && configured.isNotEmpty) {
      return configured;
    }

    final fromHost = environment['HOSTNAME'];
    if (fromHost != null && fromHost.isNotEmpty) {
      return fromHost;
    }

    final fromNamespaced = environment['OSRV_HOSTNAME'];
    if (fromNamespaced != null && fromNamespaced.isNotEmpty) {
      return fromNamespaced;
    }

    return '0.0.0.0';
  }
}
