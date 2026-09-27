import 'package:flutter/material.dart';
import '../../../domain/caja/cash_session.dart';
import '../../../domain/repositories/cash_repository.dart';
import 'cash_session_content.dart';

class CashDetailScreen extends StatelessWidget {
  const CashDetailScreen({
    super.key,
    required this.sessionId,
    required this.repository,
  });
  final String sessionId;
  final CashRepository repository;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Detalle de caja')),
    body: StreamBuilder<List<CashSession>>(
      stream: repository.watchSessions(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('No se pudo consultar la caja.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!.where((s) => s.id == sessionId);
        if (rows.isEmpty) {
          return const Center(child: Text('Caja no disponible.'));
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: CashSessionContent(session: rows.single),
        );
      },
    ),
  );
}
