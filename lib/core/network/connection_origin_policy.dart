class ConnectionOriginPolicy {
  const ConnectionOriginPolicy._();

  static bool supports(Uri origin) {
    if (origin.host.isEmpty) {
      return false;
    }
    if (origin.userInfo.isNotEmpty ||
        origin.query.isNotEmpty ||
        origin.fragment.isNotEmpty ||
        origin.path.isNotEmpty && origin.path != '/') {
      return false;
    }
    return (origin.scheme == 'http' || origin.scheme == 'https') &&
        isPrivateNetworkAddress(origin.host);
  }

  static bool isPrivateNetworkAddress(String host) {
    return _isPrivateIpv4(host) || _isUniqueLocalIpv6(host);
  }

  static bool _isPrivateIpv4(String host) {
    final octets = host.split('.').map(int.tryParse).toList();
    if (octets.length != 4 || octets.any((octet) => octet == null)) {
      return false;
    }
    final values = octets.cast<int>();
    if (values.any((octet) => octet < 0 || octet > 255)) {
      return false;
    }
    return values[0] == 10 ||
        (values[0] == 172 && values[1] >= 16 && values[1] <= 31) ||
        (values[0] == 192 && values[1] == 168);
  }

  static bool _isUniqueLocalIpv6(String host) {
    final normalized = host.toLowerCase();
    return normalized.contains(':') &&
        (normalized.startsWith('fc') || normalized.startsWith('fd'));
  }
}
