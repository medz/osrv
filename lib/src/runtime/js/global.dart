import 'dart:js_interop';

import '../../types/runtime.dart';

@JS('globalThis')
external GlobalThis get globalThis;

extension type GlobalThis._(JSObject _) implements JSObject {
  // ignore: non_constant_identifier_names
  external JSObject? get Bun;

  // ignore: non_constant_identifier_names
  external JSObject? get Deno;

  external JSObject? get process;

  // ignore: non_constant_identifier_names
  external JSAny? get EdgeRuntime;

  // ignore: non_constant_identifier_names
  external JSObject? get Netlify;

  // ignore: non_constant_identifier_names
  external JSAny? get WebSocketPair;

  external set self(JSObject value);

  @JS('__osrv_fetch__')
  external JSFunction? get osrvFetch;

  @JS('__osrv_fetch__')
  external set osrvFetch(JSFunction? value);
}

extension type NodeProcess._(JSObject _) implements JSObject {
  external NodeProcessVersions? get versions;
}

extension type NodeProcessVersions._(JSObject _) implements JSObject {
  external String? get node;
}

enum JsPlatform { node, bun, deno, cloudflare, vercel, netlify, js }

JsPlatform detectJsPlatform() {
  if (globalThis.Bun != null) {
    return JsPlatform.bun;
  }

  if (globalThis.Deno != null) {
    return JsPlatform.deno;
  }

  final process = globalThis.process;
  if (process != null) {
    final versions = NodeProcess._(process).versions;
    final nodeVersion = versions?.node;
    if (nodeVersion != null && nodeVersion.isNotEmpty) {
      return JsPlatform.node;
    }
  }

  if (globalThis.EdgeRuntime != null) {
    return JsPlatform.vercel;
  }

  if (globalThis.Netlify != null) {
    return JsPlatform.netlify;
  }

  if (globalThis.WebSocketPair != null) {
    return JsPlatform.cloudflare;
  }

  return JsPlatform.js;
}

Runtime runtimeForJsPlatform(JsPlatform platform) {
  return switch (platform) {
    JsPlatform.node => const Runtime(name: 'node', kind: RuntimeKind.node),
    JsPlatform.bun => const Runtime(name: 'bun', kind: RuntimeKind.bun),
    JsPlatform.deno => const Runtime(name: 'deno', kind: RuntimeKind.deno),
    JsPlatform.cloudflare => const Runtime(
      name: 'cloudflare',
      kind: RuntimeKind.cloudflare,
    ),
    JsPlatform.vercel => const Runtime(
      name: 'vercel',
      kind: RuntimeKind.vercel,
    ),
    JsPlatform.netlify => const Runtime(
      name: 'netlify',
      kind: RuntimeKind.netlify,
    ),
    JsPlatform.js => const Runtime(name: 'js', kind: RuntimeKind.js),
  };
}

void ensureNodeGlobalSelf() {
  globalThis.self = globalThis;
}
