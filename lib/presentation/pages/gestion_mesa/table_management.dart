import 'package:flutter/material.dart';

import '../../../application/commands/crear_espacio_command.dart';
import '../../../application/commands/espacio_command_service.dart';
import '../../../core/di/injection.dart';
import '../../../domain/espacios/espacio.dart';
import '../../../domain/repositories/espacio_repository.dart';
import 'models/espacio_form_result.dart';
import 'widgets/add_options_bottom_sheet.dart';
import 'widgets/espacio_form_dialog.dart';

class TableManagementScreen extends StatefulWidget {
  const TableManagementScreen({super.key});

  @override
  State<TableManagementScreen> createState() => _TableManagementScreenState();
}

class _TableManagementScreenState extends State<TableManagementScreen> {
  final EspacioRepository _espacioRepository = getIt<EspacioRepository>();
  final EspacioCommandService _espacioCommandService =
      getIt<EspacioCommandService>();

  Espacio? _espacioSeleccionado;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GESTION DE LA MESA'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          SizedBox(
            height: 50,
            child: StreamBuilder<List<Espacio>>(
              stream: _espacioRepository.watchEspacios(),
              builder: (context, snapshot) {
                final espaciosList = snapshot.data ?? [];
                return ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    FilterChip(
                      label: const Text('TODO'),
                      selected: _espacioSeleccionado == null,
                      onSelected: (bool value) {
                        setState(() => _espacioSeleccionado = null);
                      },
                    ),
                    const SizedBox(width: 8),
                    ...espaciosList.map((espacio) {
                      final isSelected = _espacioSeleccionado?.id == espacio.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(espacio.nombre),
                          selected: isSelected,
                          onSelected: (bool selected) {
                            setState(() {
                              _espacioSeleccionado = selected ? espacio : null;
                            });
                          },
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
          const Expanded(child: SizedBox.shrink()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _mostrarMenuOpciones(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _mostrarMenuOpciones(BuildContext context) {
    AddOptionsBottomSheet.show(
      context: context,
      onAgregarMesa: () {},
      onAgregarEspacio: () => _abrirFormularioEspacio(context),
    );
  }

  Future<void> _abrirFormularioEspacio(BuildContext context) async {
    final resultado = await showDialog<EspacioFormResult>(
      context: context,
      builder: (_) => const EspacioFormDialog(),
    );

    if (resultado == null) return;

    await _espacioCommandService.crearEspacio(
      CrearEspacioCommand(
        nombre: resultado.titulo,
        identificacion: resultado.identificacion.isEmpty
            ? null
            : resultado.identificacion,
        visibilidad: resultado.visibilidad,
      ),
    );
  }
}
