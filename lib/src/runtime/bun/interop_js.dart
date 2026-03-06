@JS()
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('globalThis')
external JSObject get _globalThis;

@JS('Bun')
external JSObject? get _bunGlobal;

extension type BunHostObject._(JSObject _) implements JSObject {}

extension type BunGlobal._(JSObject _) implements JSObject {
  external JSString? get version;
  @JS('serve')
  external JSFunction? get serve;
}

extension type BunServerHost._(JSObject _) implements JSObject {
  external JSNumber? get port;
  external JSFunction get stop;
}

BunHostObject? get globalThis => BunHostObject._(_globalThis);

BunGlobal? get bunGlobal {
  final value = _bunGlobal;
  if (value == null) {
    return null;
  }

  return BunGlobal._(value);
}

String? bunVersion(BunGlobal bun) => bun.version?.toDart;

bool bunHasServe(BunGlobal bun) => bun.serve != null;

BunServerHost bunServe(
  BunGlobal bun, {
  required String host,
  required int port,
  required Object fetch,
}) {
  final options = JSObject()
    ..setProperty('port'.toJS, port.toJS)
    ..setProperty('hostname'.toJS, host.toJS)
    ..setProperty('fetch'.toJS, fetch as JSAny);

  final server = bun.callMethodVarArgs<JSObject>(
    'serve'.toJS,
    [options],
  );
  return BunServerHost._(server);
}

int? bunServerPort(BunServerHost server) => server.port?.toDartInt;

Future<void> stopBunServer(
  BunServerHost server, {
  bool force = false,
}) async {
  final result = server.stop.callAsFunction(
    server,
    force.toJS,
  );
  if (result != null) {
    await (result as JSPromise<JSAny?>).toDart;
  }
}
