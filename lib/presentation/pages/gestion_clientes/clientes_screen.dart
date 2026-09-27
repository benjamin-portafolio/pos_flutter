import 'package:flutter/material.dart';

import '../../../application/commands/clientes/cliente_command_service.dart';
import '../../../application/commands/clientes/crear_cliente_command.dart';
import '../../../core/di/injection.dart';
import '../../../domain/clientes/cliente.dart';
import '../../../domain/clientes/cliente_resumen.dart';
import '../../../domain/repositories/cliente_repository.dart';
import '../../../domain/repositories/cliente_resumen_repository.dart';
import 'cliente_account_screen.dart';
import 'cliente_form_screen.dart';
import 'models/cliente_resumen_query.dart';
import 'widgets/cliente_resumen_card.dart';

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({
    this.repository,
    this.commandService,
    this.resumenRepository,
    super.key,
  });
  final ClienteRepository? repository;
  final ClienteCommandService? commandService;
  final ClienteResumenRepository? resumenRepository;
  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen>
    with SingleTickerProviderStateMixin {
  late final Stream<List<ClienteResumen>> _resumen;
  late final TabController _tabs;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _resumen = (widget.resumenRepository ??
            getIt<ClienteResumenRepository>())
        .watchResumen();
    _tabs = TabController(
      length: ClienteResumenTab.values.length,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
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

  void _open(ClienteResumen resumen) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ClienteAccountScreen(
          cliente: Cliente(
            id: resumen.id,
            nombre: resumen.nombre,
            telefono: resumen.telefono,
            active: resumen.active,
          ),
          clienteRepository: widget.repository,
          commandService: widget.commandService,
        ),
      ),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Gestión de clientes')),
    body: SafeArea(
      child: StreamBuilder<List<ClienteResumen>>(
        stream: _resumen,
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
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: _searchField(),
              ),
              TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(text: 'Todos los clientes'),
                  Tab(text: 'Clientes con adeudo'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _lista(clientes, ClienteResumenTab.todos),
                    _lista(clientes, ClienteResumenTab.conAdeudo),
                  ],
                ),
              ),
            ],
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

  Widget _searchField() => TextField(
    key: const Key('clientes_search_field'),
    controller: _searchController,
    decoration: InputDecoration(
      hintText: 'Buscar clientes por nombre',
      prefixIcon: const Icon(Icons.search),
      suffixIcon: _query.isEmpty
          ? null
          : IconButton(
              key: const Key('clientes_search_clear'),
              tooltip: 'Limpiar búsqueda',
              onPressed: _clearSearch,
              icon: const Icon(Icons.clear),
            ),
      border: const OutlineInputBorder(),
      isDense: true,
    ),
    onChanged: (value) => setState(() => _query = value),
  );

  Widget _lista(List<ClienteResumen> clientes, ClienteResumenTab tab) {
    final items = ClienteResumenQuery.apply(
      clientes,
      tab: tab,
      search: _query,
    );
    if (items.isEmpty) return _emptyState(tab);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final resumen = items[index];
        return ClienteResumenCard(
          key: ValueKey('cliente_resumen_${resumen.id}'),
          resumen: resumen,
          destacarAdeudo: tab == ClienteResumenTab.conAdeudo,
          onTap: () => _open(resumen),
        );
      },
    );
  }

  Widget _emptyState(ClienteResumenTab tab) {
    if (_query.trim().isNotEmpty) {
      return const Center(child: Text('No hay clientes que coincidan.'));
    }
    return Center(
      child: Text(
        tab == ClienteResumenTab.todos
            ? 'Aún no hay clientes.'
            : 'No hay clientes con adeudo.',
      ),
    );
  }
}