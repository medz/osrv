import 'package:ht/ht.dart' show Response;

abstract interface class ServerWebSocket {
  Stream<Object> get messages;

  bool get isOpen;

  Future<void> sendText(String data);

  Future<void> sendBytes(List<int> data);

  Future<void> close({int? code, String? reason});

  Future<void> done();

  Response toResponse();
}
