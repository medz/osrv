import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:relic/relic.dart';

Future<void> main(List<String> args) async {
  final app = RelicApp()
    ..get('/text', (_) => Response.ok(body: Body.fromString('ok')))
    ..post('/json', (request) async {
      final decoded = jsonDecode(await request.readAsString());
      return Response.ok(
        body: Body.fromString(
          jsonEncode(<String, Object?>{
            'ok': true,
            'type': decoded.runtimeType.toString(),
          }),
        ),
      );
    });

  final server = await app.serve(
    address: InternetAddress.loopbackIPv4,
    port: _readPort(args),
  );
  await Completer<void>().future;
  await server.close(force: true);
}

int _readPort(List<String> args) {
  final fromArg = _readIntArg(args, '--port');
  if (fromArg != null) {
    return fromArg;
  }
  final raw = Platform.environment['PORT'];
  final parsed = raw == null ? null : int.tryParse(raw);
  return parsed ?? 3000;
}

int? _readIntArg(List<String> args, String name) {
  for (final arg in args) {
    if (arg.startsWith('$name=')) {
      return int.tryParse(arg.substring(name.length + 1));
    }
  }
  return null;
}
