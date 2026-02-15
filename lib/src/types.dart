import 'dart:async';

import 'package:ht/ht.dart' show Response;

import 'request.dart';

/// Unified fetch handler for all runtimes.
typedef FetchHandler = FutureOr<Response> Function(ServerRequest request);

/// Middleware continuation function.
typedef Next = Future<Response> Function();

/// Onion-style middleware.
typedef Middleware =
    Future<Response> Function(ServerRequest request, Next next);

/// Error handler used for request and lifecycle failures.
typedef ErrorHandler =
    FutureOr<Response> Function(
      Object error,
      StackTrace stackTrace,
      ServerRequest? request,
    );

/// Wait-until function used by request/runtime contexts.
typedef WaitUntil = void Function(Future<Object?> task);

enum ServerProtocol { http, https }

enum ErrorStage {
  register,
  beforeServe,
  afterServe,
  request,
  beforeClose,
  afterClose,
  transport,
  unknown,
}

/// Stable capability flags exposed by [Server].
final class ServerCapabilities {
  const ServerCapabilities({
    required this.http1,
    required this.https,
    required this.http2,
    required this.websocket,
    required this.requestStreaming,
    required this.responseStreaming,
    required this.waitUntil,
    required this.edge,
    required this.tls,
    this.edgeProviders = const <String>{},
  });

  final bool http1;
  final bool https;
  final bool http2;
  final bool websocket;
  final bool requestStreaming;
  final bool responseStreaming;
  final bool waitUntil;
  final bool edge;
  final bool tls;
  final Set<String> edgeProviders;

  static const ServerCapabilities none = ServerCapabilities(
    http1: false,
    https: false,
    http2: false,
    websocket: false,
    requestStreaming: false,
    responseStreaming: false,
    waitUntil: false,
    edge: false,
    tls: false,
  );

  Map<String, Object> toJson() {
    return <String, Object>{
      'http1': http1,
      'https': https,
      'http2': http2,
      'websocket': websocket,
      'requestStreaming': requestStreaming,
      'responseStreaming': responseStreaming,
      'waitUntil': waitUntil,
      'edge': edge,
      'tls': tls,
      'edgeProviders': edgeProviders.toList(growable: false),
    };
  }
}

/// Unified runtime raw handles. Every field is optional by design.
final class RuntimeRawContext {
  const RuntimeRawContext({
    this.node,
    this.bun,
    this.deno,
    this.dartRequest,
    this.dartResponse,
    this.cloudflare,
    this.vercel,
    this.netlify,
  });

  final Object? node;
  final Object? bun;
  final Object? deno;
  final Object? dartRequest;
  final Object? dartResponse;
  final Object? cloudflare;
  final Object? vercel;
  final Object? netlify;
}

/// Stable runtime context attached to every request.
final class RequestRuntimeContext {
  const RequestRuntimeContext({
    required this.name,
    required this.protocol,
    required this.httpVersion,
    required this.tls,
    required this.waitUntil,
    this.localAddress,
    this.remoteAddress,
    this.env = const <String, Object?>{},
    this.raw = const RuntimeRawContext(),
  });

  final String name;
  final String protocol;
  final String httpVersion;
  final String? localAddress;
  final String? remoteAddress;
  final bool tls;
  final WaitUntil waitUntil;
  final Map<String, Object?> env;
  final RuntimeRawContext raw;
}

/// Server-facing logging abstraction.
abstract interface class ServerLogger {
  const ServerLogger();

  void info(String message);
  void warn(String message);
  void error(String message, [Object? error, StackTrace? stackTrace]);
}

/// Default logger implementation.
final class StdServerLogger implements ServerLogger {
  const StdServerLogger();

  @override
  void info(String message) => Zone.current.print('[osrv] INFO  $message');

  @override
  void warn(String message) => Zone.current.print('[osrv] WARN  $message');

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    Zone.current.print('[osrv] ERROR $message');
    if (error != null) {
      Zone.current.print('[osrv] ERROR $error');
    }
    if (stackTrace != null) {
      Zone.current.print('[osrv] ERROR $stackTrace');
    }
  }
}

final class TlsOptions {
  const TlsOptions({this.cert, this.key, this.passphrase});

  final String? cert;
  final String? key;
  final String? passphrase;

  bool get isConfigured =>
      cert != null && cert!.isNotEmpty && key != null && key!.isNotEmpty;
}

final class GracefulShutdownOptions {
  const GracefulShutdownOptions({
    this.enabled = true,
    this.gracefulTimeout = const Duration(seconds: 10),
    this.forceTimeout = const Duration(seconds: 30),
  });

  const GracefulShutdownOptions.disabled()
    : enabled = false,
      gracefulTimeout = Duration.zero,
      forceTimeout = Duration.zero;

  final bool enabled;
  final Duration gracefulTimeout;
  final Duration forceTimeout;
}

final class ServerSecurityLimits {
  const ServerSecurityLimits({
    this.maxRequestBodyBytes = 10 * 1024 * 1024,
    this.requestTimeout = const Duration(seconds: 30),
    this.headersTimeout = const Duration(seconds: 15),
    this.gracefulTimeout = const Duration(seconds: 10),
  });

  final int maxRequestBodyBytes;
  final Duration requestTimeout;
  final Duration headersTimeout;
  final Duration gracefulTimeout;
}

final class WebSocketLimits {
  const WebSocketLimits({
    this.maxFrameBytes = 1024 * 1024,
    this.idleTimeout = const Duration(seconds: 60),
    this.maxBufferedBytes = 8 * 1024 * 1024,
  });

  final int maxFrameBytes;
  final Duration idleTimeout;
  final int maxBufferedBytes;
}

final class NodeOptions {
  const NodeOptions({this.http2, this.extra = const <String, Object?>{}});

  final bool? http2;
  final Map<String, Object?> extra;
}

final class BunOptions {
  const BunOptions({this.extra = const <String, Object?>{}});

  final Map<String, Object?> extra;
}

final class DenoOptions {
  const DenoOptions({this.extra = const <String, Object?>{}});

  final Map<String, Object?> extra;
}

final class CloudflareOptions {
  const CloudflareOptions({this.extra = const <String, Object?>{}});

  final Map<String, Object?> extra;
}

final class VercelOptions {
  const VercelOptions({this.extra = const <String, Object?>{}});

  final Map<String, Object?> extra;
}

final class NetlifyOptions {
  const NetlifyOptions({this.extra = const <String, Object?>{}});

  final Map<String, Object?> extra;
}

/// Public surface exposed to plugins.
abstract interface class ServerHandle {
  bool get isServing;
  String? get url;
  ServerCapabilities get capabilities;
}

final class RegisterPluginContext {
  const RegisterPluginContext({required this.server});

  final ServerHandle server;
}

final class BeforeServePluginContext {
  const BeforeServePluginContext({required this.server});

  final ServerHandle server;
}

final class AfterServePluginContext {
  const AfterServePluginContext({required this.server});

  final ServerHandle server;
}

final class BeforeClosePluginContext {
  const BeforeClosePluginContext({required this.server, required this.force});

  final ServerHandle server;
  final bool force;
}

final class AfterClosePluginContext {
  const AfterClosePluginContext({required this.server, required this.force});

  final ServerHandle server;
  final bool force;
}

final class ErrorPluginContext {
  const ErrorPluginContext({
    required this.server,
    required this.stage,
    required this.error,
    required this.stackTrace,
    this.request,
  });

  final ServerHandle server;
  final ErrorStage stage;
  final Object error;
  final StackTrace stackTrace;
  final ServerRequest? request;
}

/// Plugin API with full lifecycle hooks.
abstract class ServerPlugin {
  const ServerPlugin();

  FutureOr<void> onRegister(RegisterPluginContext context) {}

  FutureOr<void> onBeforeServe(BeforeServePluginContext context) {}

  FutureOr<void> onAfterServe(AfterServePluginContext context) {}

  FutureOr<void> onBeforeClose(BeforeClosePluginContext context) {}

  FutureOr<void> onAfterClose(AfterClosePluginContext context) {}

  FutureOr<void> onError(ErrorPluginContext context) {}
}
