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
    TlsOptions? tls,
    this.trustProxy = false,
    ServerLogger? logger,
    this.securityLimits = const ServerSecurityLimits(),
    this.webSocketLimits = const WebSocketLimits(),
    NodeOptions node = const NodeOptions(<String, Object?>{}),
    BunOptions bun = const BunOptions(<String, Object?>{}),
    DenoOptions deno = const DenoOptions(<String, Object?>{}),
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
       tls = _resolveTls(tls, environment ?? readRuntimeEnvironment()),
       node = _resolveNodeOptions(
         node,
         environment ?? readRuntimeEnvironment(),
       ),
       bun = _resolveBunOptions(bun, environment ?? readRuntimeEnvironment()),
       deno = _resolveDenoOptions(
         deno,
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
       _resolvedProtocol = _resolveProtocol(
         protocol,
         tls,
         environment ?? readRuntimeEnvironment(),
       ) {
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

  @override
  Map<String, String> get runtimeEnvironment => _environment;

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

  static ServerProtocol _resolveProtocol(
    ServerProtocol? configured,
    TlsOptions? tls,
    Map<String, String> environment,
  ) {
    if (configured != null) {
      return configured;
    }

    final envProtocol = (environment['OSRV_PROTOCOL'] ?? '').toLowerCase();
    if (envProtocol == 'https') {
      return ServerProtocol.https;
    }
    if (envProtocol == 'http') {
      return ServerProtocol.http;
    }

    final tlsConfigured = tls?.isConfigured ?? false;
    if (tlsConfigured || _hasTlsEnvironmentInputs(environment)) {
      return ServerProtocol.https;
    }

    final tlsRequested = _parseBoolish(environment['OSRV_TLS']);
    if (tlsRequested == true) {
      return ServerProtocol.https;
    }

    return ServerProtocol.http;
  }

  static TlsOptions? _resolveTls(
    TlsOptions? configured,
    Map<String, String> environment,
  ) {
    final cert = _firstNonEmptyString(
      configured?.cert,
      environment['OSRV_TLS_CERT'],
      environment['TLS_CERT'],
    );
    final key = _firstNonEmptyString(
      configured?.key,
      environment['OSRV_TLS_KEY'],
      environment['TLS_KEY'],
    );
    final passphrase = _firstNonEmptyString(
      configured?.passphrase,
      environment['OSRV_TLS_PASSPHRASE'],
      environment['TLS_PASSPHRASE'],
    );

    if (cert == null && key == null && passphrase == null) {
      return null;
    }

    return TlsOptions(cert: cert, key: key, passphrase: passphrase);
  }

  static NodeOptions _resolveNodeOptions(
    NodeOptions configured,
    Map<String, String> environment,
  ) {
    final values = <String, Object?>{};

    final http2 = _parseBoolish(
      _firstNonEmptyString(
        environment['OSRV_NODE_HTTP2'],
        environment['OSRV_HTTP2'],
      ),
    );
    if (http2 != null) {
      values['http2'] = http2;
    }

    final maxHeaderSize = int.tryParse(
      environment['OSRV_NODE_MAX_HEADER_SIZE'] ?? '',
    );
    if (maxHeaderSize != null) {
      values['maxHeaderSize'] = maxHeaderSize;
    }

    values.addAll(configured);
    return NodeOptions(values);
  }

  static BunOptions _resolveBunOptions(
    BunOptions configured,
    Map<String, String> environment,
  ) {
    final values = <String, Object?>{};

    final http2 = _parseBoolish(
      _firstNonEmptyString(
        environment['OSRV_BUN_HTTP2'],
        environment['OSRV_HTTP2'],
      ),
    );
    if (http2 != null) {
      values['http2'] = http2;
    }

    final idleTimeoutMs = int.tryParse(
      environment['OSRV_BUN_IDLE_TIMEOUT_MS'] ?? '',
    );
    if (idleTimeoutMs != null) {
      values['idleTimeoutMs'] = idleTimeoutMs;
    }

    final reusePort = _parseBoolish(environment['OSRV_BUN_REUSE_PORT']);
    if (reusePort != null) {
      values['reusePort'] = reusePort;
    }

    values.addAll(configured);
    return BunOptions(values);
  }

  static DenoOptions _resolveDenoOptions(
    DenoOptions configured,
    Map<String, String> environment,
  ) {
    final values = <String, Object?>{};

    final http2 = _parseBoolish(
      _firstNonEmptyString(
        environment['OSRV_DENO_HTTP2'],
        environment['OSRV_HTTP2'],
      ),
    );
    if (http2 != null) {
      values['http2'] = http2;
    }

    values.addAll(configured);
    return DenoOptions(values);
  }

  static bool _hasTlsEnvironmentInputs(Map<String, String> environment) {
    final cert = _firstNonEmptyString(
      environment['OSRV_TLS_CERT'],
      environment['TLS_CERT'],
    );
    final key = _firstNonEmptyString(
      environment['OSRV_TLS_KEY'],
      environment['TLS_KEY'],
    );
    return cert != null && key != null;
  }

  static String? _firstNonEmptyString(
    String? first,
    String? second, [
    String? third,
  ]) {
    for (final value in <String?>[first, second, third]) {
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    return null;
  }

  static bool? _parseBoolish(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'on') {
      return true;
    }
    if (normalized == '0' ||
        normalized == 'false' ||
        normalized == 'no' ||
        normalized == 'off') {
      return false;
    }

    return null;
  }
}
