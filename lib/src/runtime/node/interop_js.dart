// ignore_for_file: public_member_api_docs

@JS()
library;

import 'dart:js_interop';

@JS('globalThis')
external JSObject get _globalThis;

@JS('process')
external JSObject? get _nodeProcess;

extension type NodeHostObject._(JSObject _) implements JSObject {}

extension type NodeProcess._(JSObject _) implements JSObject {
  external JSString get version;
  external NodeProcessVersions get versions;
  external NodeProcessEnv get env;
  external JSFunction? get getBuiltinModule;
}

extension type NodeProcessVersions._(JSObject _) implements JSObject {
  external JSString? get node;
}

extension type NodeProcessEnv._(JSObject _) implements JSObject {}

extension type NodeServerHost._(JSObject _) implements JSObject {
  external JSFunction get listen;
  external JSFunction get close;
}

extension type NodeRequestHost._(JSObject _) implements JSObject {
  external JSAny? get method;
  external JSAny? get url;
  external JSAny? get headers;
}

extension type NodeResponseHost._(JSObject _) implements JSObject {
  @JS('setHeader')
  external JSFunction get setHeader;

  external JSFunction get end;

  external JSAny? get statusCode;
  external JSAny? get statusMessage;
}

NodeHostObject? get globalThis => NodeHostObject._(_globalThis);

NodeProcess? get nodeProcess {
  final value = _nodeProcess;
  if (value == null) {
    return null;
  }

  return NodeProcess._(value);
}

String? nodeProcessVersion(NodeProcess process) {
  return process.versions.node?.toDart ?? process.version.toDart;
}
