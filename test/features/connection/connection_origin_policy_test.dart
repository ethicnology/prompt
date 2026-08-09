import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/connection/domain/connection_origin_policy.dart';

void main() {
  group('ConnectionOriginPolicy', () {
    test('accepts RFC1918 WireGuard IPv4 origins over HTTP', () {
      expect(
        ConnectionOriginPolicy.supports(Uri.parse('http://10.80.0.1:4096')),
        isTrue,
      );
      expect(
        ConnectionOriginPolicy.supports(Uri.parse('http://172.20.0.5:4096')),
        isTrue,
      );
      expect(
        ConnectionOriginPolicy.supports(Uri.parse('http://192.168.42.1:4096')),
        isTrue,
      );
    });

    test('accepts IPv6 unique local addresses over HTTP', () {
      expect(
        ConnectionOriginPolicy.supports(Uri.parse('http://[fd00::1]:4096')),
        isTrue,
      );
    });

    test('accepts Tailscale CGNAT IPv4 origins over HTTP', () {
      expect(
        ConnectionOriginPolicy.supports(Uri.parse('http://100.64.0.1:4096')),
        isTrue,
      );
      expect(
        ConnectionOriginPolicy.supports(Uri.parse('http://100.127.255.255')),
        isTrue,
      );
      expect(
        ConnectionOriginPolicy.supports(Uri.parse('http://100.128.0.1')),
        isFalse,
      );
    });

    test('rejects public origins even when they use HTTPS', () {
      expect(
        ConnectionOriginPolicy.supports(Uri.parse('http://198.51.100.1:4096')),
        isFalse,
      );
      expect(
        ConnectionOriginPolicy.supports(
          Uri.parse('https://opencode.example.test'),
        ),
        isFalse,
      );
      expect(
        ConnectionOriginPolicy.supports(Uri.parse('https://10.80.0.1:4096')),
        isTrue,
      );
    });
  });
}
