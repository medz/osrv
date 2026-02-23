import '../core/config.dart';
import 'js/bun_server.dart';
import 'js/deno_server.dart';
import 'js/edge_server.dart';
import 'js/global.dart';
import 'js/node_server.dart';
import 'server_transport.dart';

ServerTransport createServerTransport({
  required ServerConfig config,
  required DispatchRequest dispatch,
  required TrackBackgroundTask trackBackgroundTask,
}) {
  return _JsServerTransport(
    config: config,
    dispatch: dispatch,
    trackBackgroundTask: trackBackgroundTask,
  );
}

final class _JsServerTransport implements ServerTransport {
  _JsServerTransport({
    required ServerConfig config,
    required DispatchRequest dispatch,
    required TrackBackgroundTask trackBackgroundTask,
  }) : _delegate = _selectPlatform(
         config: config,
         dispatch: dispatch,
         trackBackgroundTask: trackBackgroundTask,
       );

  final ServerTransport _delegate;

  static ServerTransport _selectPlatform({
    required ServerConfig config,
    required DispatchRequest dispatch,
    required TrackBackgroundTask trackBackgroundTask,
  }) {
    final platform = detectJsPlatform();

    return switch (platform) {
      JsPlatform.node => () {
        ensureNodeGlobalSelf();
        return NodeServerTransport(config: config, dispatch: dispatch);
      }(),
      JsPlatform.bun => BunServerTransport(config: config, dispatch: dispatch),
      JsPlatform.deno => DenoServerTransport(
        config: config,
        dispatch: dispatch,
      ),
      JsPlatform.cloudflare ||
      JsPlatform.vercel ||
      JsPlatform.netlify ||
      JsPlatform.js => EdgeServerTransport(
        platform: platform,
        config: config,
        dispatch: dispatch,
        trackBackgroundTask: trackBackgroundTask,
      ),
    };
  }

  @override
  get runtime => _delegate.runtime;

  @override
  String get hostname => _delegate.hostname;

  @override
  int get port => _delegate.port;

  @override
  Uri get url => _delegate.url;

  @override
  String get addr => _delegate.addr;

  @override
  Future<void> serve() => _delegate.serve();

  @override
  Future<void> ready() => _delegate.ready();

  @override
  Future<void> close({required bool force}) => _delegate.close(force: force);
}
