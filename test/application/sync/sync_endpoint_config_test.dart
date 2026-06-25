import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';

void main() {
  group('SyncEndpointConfig', () {
    test('normalizes an IP without scheme or port', () {
      final result = SyncEndpointConfig.normalizeBaseUrl('192.168.1.20');

      expect(result, 'http://192.168.1.20:3000');
    });

    test('keeps a full URL with an explicit port', () {
      final result = SyncEndpointConfig.normalizeBaseUrl(
        'http://127.0.0.1:4000',
      );

      expect(result, 'http://127.0.0.1:4000');
    });

    test('keeps a full HTTPS ngrok URL without adding port 3000', () {
      final result = SyncEndpointConfig.normalizeBaseUrl(
        'https://cf6d-206-135-11-146.ngrok-free.app',
      );

      expect(result, 'https://cf6d-206-135-11-146.ngrok-free.app');
    });

    test('rejects an empty server value', () {
      expect(
        () => SyncEndpointConfig.normalizeBaseUrl(''),
        throwsFormatException,
      );
    });
  });
}
