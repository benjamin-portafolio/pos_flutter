import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../domain/clientes/cliente.dart';
import '../../../domain/repositories/cliente_repository.dart';
import 'clientes_screen.dart';

class ClientePickerScreen extends StatefulWidget {
  const ClientePickerScreen({super.key, this.repository});
  final ClienteRepository? repository;
  @override
  State<ClientePickerScreen> createState() => _ClientePickerScreenState();
}

class _ClientePickerScreenState extends State<ClientePickerScreen> {
  late final _clientes = (widget.repository ?? getIt<ClienteRepository>())
      .watchClientes();
  String _query = '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Seleccionar cliente')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Buscar por nombre o teléfono',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Cliente>>(
            stream: _clientes,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('No se pudieron cargar los clientes.'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data!
                  .where((c) => c.active)
                  .where(
                    (c) =>
                        c.nombre.toLowerCase().contains(_query) ||
                        (c.telefono ?? '').contains(_query),
                  )
                  .toList();
              if (rows.isEmpty) {
                return const Center(
                  child: Text('No hay clientes que coincidan.'),
                );
              }
              return ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) => ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(rows[i].nombre),
                  subtitle: Text(rows[i].telefono ?? 'Sin teléfono'),
                  onTap: () => Navigator.pop(context, rows[i]),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const ClientesScreen()),
            ),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Gestionar / agregar clientes'),
          ),
        ),
      ],
    ),
  );
}
