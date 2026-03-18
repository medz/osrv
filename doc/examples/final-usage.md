# osrv Usage Examples

These examples match the current implementation.

If you want runtime-specific setup and limits, see [runtime docs](../runtime/README.md).

## Basic `dart` Server

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/dart.dart';

Future<void> main() async {
  final server = Server(
    fetch: (request, context) {
      return Response.json({
        'runtime': context.runtime.name,
        'path': request.url.path,
      });
    },
  );

  final runtime = await serve(
    server,
    host: '127.0.0.1',
    port: 3000,
  );

  print(runtime.url);
}
```

## Basic `node` Server

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/node.dart';

Future<void> main() async {
  final runtime = await serve(
    Server(fetch: (request, context) => Response.text('hello from node')),
    host: '127.0.0.1',
    port: 3000,
  );

  print(runtime.url);
}
```

## Basic `deno` Server

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/deno.dart';

Future<void> main() async {
  final runtime = await serve(
    Server(fetch: (request, context) => Response.text('hello from deno')),
    host: '127.0.0.1',
    port: 3000,
  );

  print(runtime.url);
}
```

## Cloudflare Fetch Entry

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/cloudflare.dart';
import 'package:web/web.dart' as web;

void main() {
  defineFetchExport(
    Server(
      fetch: (request, context) {
        final cf =
            context.extension<CloudflareRuntimeExtension<Object?, web.Request>>();
        return Response.json({
          'runtime': context.runtime.name,
          'requestUrl': cf?.request?.url,
        });
      },
    ),
  );
}
```

## Vercel Fetch Entry

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/vercel.dart';
import 'package:web/web.dart' as web;

void main() {
  defineFetchExport(
    Server(
      fetch: (request, context) {
        final vercel = context.extension<VercelRuntimeExtension<web.Request>>();
        return Response.json({
          'runtime': context.runtime.name,
          'hasFunctions': vercel?.functions != null,
        });
      },
    ),
  );
}
```

## Netlify Fetch Entry

```dart
import 'package:osrv/osrv.dart';
import 'package:osrv/runtime/netlify.dart';
import 'package:web/web.dart' as web;

void main() {
  defineFetchExport(
    Server(
      fetch: (request, context) {
        final netlify =
            context.extension<NetlifyRuntimeExtension<web.Request>>();
        return Response.json({
          'runtime': context.runtime.name,
          'requestId': netlify?.context?.requestId,
        });
      },
    ),
  );
}
```

## Capability Check

```dart
final runtime = await serve(
  server,
  port: 3000,
);

if (!runtime.capabilities.websocket) {
  // current websocket fallback
}
```

## `waitUntil(...)`

```dart
final server = Server(
  fetch: (request, context) {
    if (context.capabilities.backgroundTask) {
      context.waitUntil(Future<void>.value());
    }
    return Response.text('accepted');
  },
);
```

Use `waitUntil(...)` only when the active runtime reports `backgroundTask == true`.
