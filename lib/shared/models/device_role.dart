enum DeviceRole { start, stop, split }

extension DeviceRoleX on DeviceRole {
  String get wireValue {
    switch (this) {
      case DeviceRole.start:
        return 'start';
      case DeviceRole.stop:
        return 'stop';
      case DeviceRole.split:
        return 'split';
    }
  }

  String get label {
    switch (this) {
      case DeviceRole.start:
        return 'START';
      case DeviceRole.stop:
        return 'STOP';
      case DeviceRole.split:
        return 'SPLIT';
    }
  }
}

DeviceRole parseRole(String? raw) {
  switch (raw) {
    case 'start':
      return DeviceRole.start;
    case 'stop':
      return DeviceRole.stop;
    case 'split':
    default:
      return DeviceRole.split;
  }
}
