// ignore_for_file: public_member_api_docs

library;

import 'package:ht/ht.dart' show Request;
import 'package:web/web.dart' as web;

Request htRequestFromWebRequest(web.Request request) => Request(request);
