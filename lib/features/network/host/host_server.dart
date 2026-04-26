import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../shared/config/network_config.dart';
import '../../../shared/protocol/message_type.dart';
import '../../../shared/protocol/socket_codec.dart';
import '../../../shared/protocol/socket_envelope.dart';

typedef HostMessageHandler =
    void Function(String deviceId, SocketEnvelope envelope, int receivedAtMs);
typedef HostDeviceConnectedHandler = void Function(String deviceId);
typedef HostDeviceDisconnectedHandler = void Function(String deviceId);

class HostServer {
  HostServer({
    required this.onMessage,
    required this.onDeviceConnected,
    required this.onDeviceDisconnected,
  });

  final HostMessageHandler onMessage;
  final HostDeviceConnectedHandler onDeviceConnected;
  final HostDeviceDisconnectedHandler onDeviceDisconnected;

  HttpServer? _server;
  int _connectionCounter = 0;
  final Map<int, _Peer> _peersByConnection = <int, _Peer>{};
  final Map<String, _Peer> _peersByDevice = <String, _Peer>{};

  Future<void> start() async {
    if (_server != null) {
      return;
    }

    final handler = webSocketHandler((WebSocketChannel channel, _) {
      final connectionId = _connectionCounter++;
      final peer = _Peer(connectionId: connectionId, channel: channel);
      _peersByConnection[connectionId] = peer;

      channel.stream.listen(
        (dynamic data) => _onData(peer, data),
        onDone: () => _onDisconnect(peer),
        onError: (_) => _onDisconnect(peer),
        cancelOnError: true,
      );
    });

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, NetworkConfig.hostPort);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;

    for (final peer in _peersByConnection.values) {
      await peer.channel.sink.close();
    }

    _peersByConnection.clear();
    _peersByDevice.clear();
  }

  void _onData(_Peer peer, dynamic raw) {
    try {
      final envelope = SocketCodec.decode(raw);
      final receivedAtMs = DateTime.now().millisecondsSinceEpoch;

      if (envelope.type == MessageType.hello && envelope.deviceId.isNotEmpty) {
        peer.deviceId = envelope.deviceId;
        _peersByDevice[envelope.deviceId] = peer;
        onDeviceConnected(envelope.deviceId);
      }

      final deviceId = peer.deviceId ?? envelope.deviceId;
      onMessage(deviceId, envelope, receivedAtMs);
    } catch (_) {
      // Ignore malformed message.
    }
  }

  void _onDisconnect(_Peer peer) {
    _peersByConnection.remove(peer.connectionId);
    final deviceId = peer.deviceId;
    if (deviceId != null) {
      _peersByDevice.remove(deviceId);
      onDeviceDisconnected(deviceId);
    }
  }

  void sendToDevice(String deviceId, SocketEnvelope envelope) {
    final peer = _peersByDevice[deviceId];
    if (peer == null) {
      return;
    }
    peer.channel.sink.add(SocketCodec.encode(envelope));
  }

  void broadcast(SocketEnvelope envelope) {
    final encoded = SocketCodec.encode(envelope);
    for (final peer in _peersByConnection.values) {
      peer.channel.sink.add(encoded);
    }
  }
}

class _Peer {
  _Peer({required this.connectionId, required this.channel});

  final int connectionId;
  final WebSocketChannel channel;
  String? deviceId;
}
