import 'cliente_account_screen.dart';
import 'package:flutter/material.dart';
import '../../../application/commands/clientes/cliente_command_service.dart';
import '../../../application/commands/clientes/crear_cliente_command.dart';
import '../../../core/di/injection.dart';
import '../../../domain/clientes/cliente.dart';
import '../../../domain/repositories/cliente_repository.dart';
import 'cliente_form_screen.dart';

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({this.repository, this.commandService, super.key});
  final ClienteRepository? repository;
  final ClienteCommandService? commandService;
  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  late final Stream<List<Cliente>> _clientes;
  @override
  void initState() {
    super.initState();
    _clientes = (widget.repository ?? getIt<ClienteRepository>())
        .watchClientes();
  }

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ClienteFormScreen(
          onSave: (result) =>
              (widget.commandService ?? getIt<ClienteCommandService>())
                  .crearCliente(
                    CrearClienteCommand(
                      nombre: result.nombre,
                      telefono: result.telefono,
                    ),
                  ),
        ),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cliente guardado.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Gestión de clientes')),
    body: SafeArea(
      child: StreamBuilder<List<Cliente>>(
        stream: _clientes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('No se pudo cargar la lista de clientes.'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final clientes = snapshot.data!;
          if (clientes.isEmpty) return const SizedBox.expand();
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: clientes.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final cliente = clientes[index];
              return ListTile(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ClienteAccountScreen(
                      cliente: cliente,
                      clienteRepository: widget.repository,
                      commandService: widget.commandService,
                    ),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                leading: const Icon(Icons.person_outline),
                title: Text(cliente.nombre),
                subtitle: !cliente.active
                    ? const Text('Cuenta con incidencia · consultar historial')
                    : cliente.telefono == null
                    ? null
                    : Text(cliente.telefono!),
              );
            },
          );
        },
      ),
    ),
    floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _add,
      icon: const Icon(Icons.add),
      label: const Text('Agregar cliente'),
    ),
  );
}
