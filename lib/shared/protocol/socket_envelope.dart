class SocketEnvelope {
  const SocketEnvelope({
    required this.type,
    this.deviceId = '',
    required this.sentAtMs,
    required this.seq,
    required this.payload,
  });

  final String type;
  final String deviceId;
  final int sentAtMs;
  final int seq;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      if (deviceId.isNotEmpty) 'deviceId': deviceId,
      'sentAtMs': sentAtMs,
      'seq': seq,
      'payload': payload,
    };
  }

  factory SocketEnvelope.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return SocketEnvelope(
      type: (json['type'] ?? '').toString(),
      deviceId: (json['deviceId'] ?? '').toString(),
      sentAtMs: (json['sentAtMs'] is int)
          ? json['sentAtMs'] as int
          : int.tryParse((json['sentAtMs'] ?? '0').toString()) ?? 0,
      seq: (json['seq'] is int)
          ? json['seq'] as int
          : int.tryParse((json['seq'] ?? '0').toString()) ?? 0,
      payload: rawPayload is Map<String, dynamic>
          ? rawPayload
          : Map<String, dynamic>.from((rawPayload as Map?) ?? const <String, dynamic>{}),
    );
  }
}
