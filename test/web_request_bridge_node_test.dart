@TestOn('node')
library;

import 'dart:js_interop';

import 'package:ht/ht.dart' show HttpMethod;
import 'package:osrv/src/runtime/_internal/js/web_request_bridge.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  test('web request bridge keeps web.Request host-backed semantics', () async {
    final request = htRequestFromWebRequest(
      web.Request(
        'https://example.com/upload?q=1'.toJS,
        web.RequestInit(method: 'POST', body: 'hello world'.toJS),
      ),
    );
    final clone = request.clone();

    expect(request.method, HttpMethod.post);
    expect(request.url, 'https://example.com/upload?q=1');
    expect(request.keepalive, isFalse);
    expect(request.bodyUsed, isFalse);
    expect(await request.text(), 'hello world');
    expect(await clone.text(), 'hello world');
    expect(request.bodyUsed, isTrue);
  });
}
