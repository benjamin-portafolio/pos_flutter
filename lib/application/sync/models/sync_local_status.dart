import 'sync_problem.dart';

class SyncLocalStatus {
  const SyncLocalStatus({required this.pending, required this.problems});

  final int pending;
  final List<SyncProblem> problems;
}
