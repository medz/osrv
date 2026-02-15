import '../types.dart';
import 'server_transport.dart';

ServerTransport createServerTransport(ServerTransportHost host) {
  return _UnsupportedTransport(host);
}

final class _UnsupportedTransport implements ServerTransport {
  _UnsupportedTransport(this._host);

  final ServerTransportHost _host;

  @override
  String get runtimeName => 'generic';

  @override
  ServerCapabilities get capabilities => const ServerCapabilities(
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

  @override
  String? get url => null;

  @override
  Future<void> close({required bool force}) async {}

  @override
  Future<void> ready() async {}

  @override
  Future<void> serve() async {
    _host.logWarn(
      'Current runtime does not support native server transport. '
      'Use generated runtime adapters in dist/js or dist/edge.',
    );
  }
}
