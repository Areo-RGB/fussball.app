class NetworkConfig {
  static const String hostIp = '192.168.0.103';
  static const int hostPort = 8080;

  static String get wsUrl => 'ws://$hostIp:$hostPort';
}
