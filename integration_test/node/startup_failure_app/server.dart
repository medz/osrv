import 'dart:async';
import 'dart:js_interop';

import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/node.dart';

@JS('process.env.OSRV_TEST_PORT')
external JSString? get _osrvTestPort;

@JS('process.stdin')
external _NodeProcessStdin get _processStdin;

extension type _NodeProcessStdin._(JSObject _) implements JSObject {
  external JSFunction get once;
  external JSFunction get resume;
}

extension type _NodeEventEmitter._(JSObject _) implements JSObject {
  external JSFunction get on;
}

Future<void> main() async {
  final port = int.parse(_osrvTestPort?.toDart ?? '0');

  await serve(
    Server(
      onStart: (context) async {
        final extension = context.extension<NodeRuntimeExtension>();
        final server = extension?.server;
        if (server != null) {
          _NodeEventEmitter._(server as JSObject).on.callAsFunction(
            server as JSObject,
            'upgrade'.toJS,
            ((JSAny? _, JSAny? arg1, JSAny? arg2) {
              arg1;
              arg2;
              print('UPGRADE_SEEN');
            }).toJS,
          );
        }
        print('STARTUP_ENTERED');
        await _waitForReleaseSignal();
        throw StateError('boom');
      },
      fetch: (request, context) => Response('unreachable'),
    ),
    host: '127.0.0.1',
    port: port,
  );
}

Future<void> _waitForReleaseSignal() {
  final completer = Completer<void>();
  _processStdin.resume.callAsFunction(_processStdin);
  _processStdin.once.callAsFunction(
    _processStdin,
    'data'.toJS,
    ((JSAny? _) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }).toJS,
  );
  return completer.future;
}
