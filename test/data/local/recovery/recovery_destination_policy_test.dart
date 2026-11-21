import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/recovery/recovery_destination_policy.dart';
import 'package:pos_flutter/data/local/recovery/http_baseline_bootstrap_transport.dart';
import 'package:pos_flutter/data/local/recovery/http_recovery_destination_inspector.dart';

void main() {
  for (final host in [
    '192.168.0.202',
    '10.1.2.3',
    '172.16.0.1',
    '172.31.255.254',
  ]) {
    test(
      'HTTP local $host requiere habilitación explícita en ambos flujos',
      () {
        final url = 'http://$host:3000';
        Uri inspect() => HttpRecoveryDestinationInspector.parseDestination(url);
        HttpBaselineBootstrapTransport bootstrap() =>
            HttpBaselineBootstrapTransport(
              baseUri: Uri.parse(url),
              serverInstanceId: 'server',
              generationId: 'generation',
              enrollmentToken: 'token',
            );
        if (RecoveryDestinationPolicy.allowLocalHttp) {
          expect(inspect().toString(), url);
          bootstrap().close();
        } else {
          expect(inspect, throwsFormatException);
          expect(bootstrap, throwsFormatException);
        }
      },
    );
  }
  for (final url in [
    'http://8.8.8.8',
    'http://172.15.0.1',
    'http://172.32.0.1',
    'http://192.169.0.1',
    'http://192.168.0.999',
    'http://server.local',
    'http://user:secret@192.168.0.202',
    'http://192.168.0.202/private',
    'http://192.168.0.202?token=secret',
    'http://192.168.0.202#fragment',
  ]) {
    test('rechaza $url incluso con HTTP local habilitado', () {
      expect(() => RecoveryDestinationPolicy.parse(url), throwsFormatException);
      expect(
        () => HttpBaselineBootstrapTransport(
          baseUri: Uri.parse(url),
          serverInstanceId: 'server',
          generationId: 'generation',
          enrollmentToken: 'token',
        ),
        throwsFormatException,
      );
    });
  }
  for (final url in [
    'https://destination.test',
    'http://localhost:3000',
    'http://127.0.0.1:3000',
    'http://[::1]:3000',
  ]) {
    test('conserva HTTPS y loopback: $url', () {
      expect(RecoveryDestinationPolicy.parse(url).toString(), url);
    });
  }
}
