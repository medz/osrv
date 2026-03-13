// ignore_for_file: public_member_api_docs

import 'dart:io';

import 'package:ht/ht.dart' show Request;

Future<Request> dartRequestFromHttpRequest(HttpRequest request) async =>
    (Request as dynamic)(request) as Request;
