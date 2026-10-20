import 'scale_failure.dart';

class ScaleException implements Exception {
  const ScaleException(this.failure, {this.nativeCode});

  final ScaleFailure failure;
  final int? nativeCode;

  @override
  String toString() => 'ScaleException(${failure.name}, $nativeCode)';
}
