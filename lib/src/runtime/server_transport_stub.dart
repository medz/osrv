import '../core/config.dart';
import '../types/runtime.dart';
import 'server_transport.dart';

ServerTransport createServerTransport({
  required ServerConfig config,
  required DispatchRequest dispatch,
  required TrackBackgroundTask trackBackgroundTask,
}) {
  return _UnsupportedServerTransport(config);
}

final class _UnsupportedServerTransport implements ServerTransport {
  _UnsupportedServerTransport(this._config);

  final ServerConfig _config;

  @override
  Runtime get runtime =>
      const Runtime(name: 'unsupported', kind: RuntimeKind.unknown);

  @override
  String get hostname => _config.hostname;

  @override
  int get port => _config.port;

  @override
  Uri get url => _config.defaultUrl();

  @override
  String get addr => '$hostname:$port';

  @override
  Future<void> serve() {
    throw UnsupportedError('No supported runtime transport for this platform.');
  }

  @override
  Future<void> ready() => Future<void>.value();

  @override
  Future<void> close({required bool force}) => Future<void>.value();
}
