import 'dart:convert';

import 'socket_envelope.dart';

class SocketCodec {
  static String encode(SocketEnvelope envelope) => jsonEncode(envelope.toJson());

  static SocketEnvelope decode(dynamic raw) {
    final decoded = jsonDecode(raw.toString()) as Map<String, dynamic>;
    return SocketEnvelope.fromJson(decoded);
  }
}
