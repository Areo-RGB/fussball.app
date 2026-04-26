import 'dart:async';
import 'dart:io';

import 'package:web_socket_channel/io.dart';

import '../../../shared/config/network_config.dart';
import '../../../shared/protocol/socket_codec.dart';
import '../../../shared/protocol/socket_envelope.dart';

enum ClientConnectionState { connecting, connected, disconnected }

typedef EnvelopeHandler = void Function(SocketEnvelope envelope);
typedef ConnectionStateHandler = void Function(ClientConnectionState state);

class ClientConnection {
  ClientConnection({required this.onEnvelope, required this.onStateChanged});

  final EnvelopeHandler onEnvelope;
  final ConnectionStateHandler onStateChanged;

  IOWebSocketChannel? _channel;
  Timer? _reconnectTimer;
  bool _running = false;
  int _seq = 0;

  Future<void> start() async {
    _running = true;
    await _connect();
  }

  Future<void> _connect() async {
    if (!_running) {
      return;
    }

    onStateChanged(ClientConnectionState.connecting);

    try {
      final socket = await WebSocket.connect(NetworkConfig.wsUrl);
      _channel = IOWebSocketChannel(socket);
      onStateChanged(ClientConnectionState.connected);

      _channel!.stream.listen(
        (dynamic data) {
          try {
            final envelope = SocketCodec.decode(data);
            onEnvelope(envelope);
          } catch (_) {
            // Ignore malformed messages.
          }
        },
        onDone: _handleDisconnect,
        onError: (_) => _handleDisconnect(),
      );
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _channel = null;
    onStateChanged(ClientConnectionState.disconnected);
    _reconnectTimer?.cancel();

    if (_running) {
      _reconnectTimer = Timer(const Duration(seconds: 2), () {
        unawaited(_connect());
      });
    }
  }

  bool send({required String type, String deviceId = '', required Map<String, dynamic> payload}) {
    final channel = _channel;
    if (channel == null) {
      return false;
    }

    final envelope = SocketEnvelope(
      type: type,
      deviceId: deviceId,
      sentAtMs: DateTime.now().millisecondsSinceEpoch,
      seq: _seq++,
      payload: payload,
    );

    channel.sink.add(SocketCodec.encode(envelope));
    return true;
  }

  Future<void> close() async {
    _running = false;
    _reconnectTimer?.cancel();
    await _channel?.sink.close();
    _channel = null;
  }
}
