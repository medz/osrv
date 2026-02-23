import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:ht/ht.dart' as ht;
import 'package:web/web.dart' as web;

import '../../request.dart';

extension type _UnderlyingSource._(JSObject _) implements JSObject {
  external factory _UnderlyingSource({
    JSFunction? start,
    JSFunction? cancel,
    String? type,
  });
}

extension on web.Headers {
  @JS('forEach')
  external void _forEach(JSFunction callback);
}

extension on web.ReadableStream {
  Stream<Uint8List> toDartBytesStream() async* {
    final reader = getReader() as web.ReadableStreamDefaultReader;
    try {
      while (true) {
        final result = await reader.read().toDart;
        if (result.done) {
          break;
        }
        if (result.value == null) {
          continue;
        }
        yield (result.value as JSUint8Array).toDart;
      }
    } finally {
      reader.releaseLock();
    }
  }
}

ht.Headers webHeadersToHtHeaders(web.Headers source) {
  final headers = ht.Headers();

  void collect(String value, String name) {
    headers.append(name, value);
  }

  source._forEach(collect.toJS);
  for (final cookie in source.getSetCookie().toDart) {
    headers.append('set-cookie', cookie.toDart);
  }
  return headers;
}

web.Headers htHeadersToWebHeaders(ht.Headers source) {
  final headers = web.Headers();
  for (final entry in source) {
    headers.append(entry.key, entry.value);
  }
  return headers;
}

web.ReadableStream dartBytesToReadableStream(Stream<Uint8List> bytes) {
  late final StreamSubscription<Uint8List> subscription;

  void start(web.ReadableStreamDefaultController controller) {
    subscription = bytes.listen(
      (chunk) => controller.enqueue(chunk.toJS),
      onError: (error, stackTrace) {
        controller.error('$error\n$stackTrace'.toJS);
      },
      onDone: () => controller.close(),
    );
  }

  void cancel() {
    unawaited(subscription.cancel());
  }

  return web.ReadableStream(
    _UnderlyingSource(type: 'bytes', start: start.toJS, cancel: cancel.toJS),
  );
}

ServerRequest webRequestToServerRequest(
  web.Request request, {
  String? ip,
  WaitUntil? waitUntil,
  Map<String, Object?>? context,
}) {
  final body = request.body?.toDartBytesStream();
  final fetchRequest = ht.Request(
    Uri.parse(request.url),
    method: request.method,
    headers: webHeadersToHtHeaders(request.headers),
    body: body,
  );

  return createServerRequest(
    fetchRequest,
    ip: ip,
    waitUntil: waitUntil,
    context: context,
  );
}

Future<web.Response> htResponseToWebResponse(ht.Response response) async {
  final bodyStream = response.body;

  return web.Response(
    bodyStream == null ? null : dartBytesToReadableStream(bodyStream),
    web.ResponseInit(
      status: response.status,
      statusText: response.statusText,
      headers: htHeadersToWebHeaders(response.headers),
    ),
  );
}
