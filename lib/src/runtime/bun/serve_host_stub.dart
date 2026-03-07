// ignore_for_file: public_member_api_docs

import '../../core/runtime.dart';
import '../../core/server.dart';
import 'preflight.dart';

Future<Runtime> serveBunRuntimeHost(
  Server _,
  BunRuntimePreflight preflight,
) {
  throw preflight.toUnsupportedError();
}
