import 'package:flutter/material.dart';
/*import 'package:punto_venta/data/local/dao/espacio_dao.dart';
import 'package:punto_venta/data/local/db_helper.dart';
import 'package:punto_venta/data/models/espacio_model.dart';
import 'package:punto_venta/data/models/synchronization/synchronization_response.dart';
import 'package:punto_venta/data/remote/synchronization/synchronization_api_service.dart';
import 'package:punto_venta/presentation/pages/alta_espacios/alta_espacios_screen.dart';
import 'package:punto_venta/presentation/pages/pruebas_screen.dart';
import 'package:web_socket_channel/web_socket_channel.dart';*/

import 'models/espacio_form_result.dart';
import 'models/mesa_form_result.dart';
import 'widgets/add_options_bottom_sheet.dart';
import 'widgets/espacio_form_dialog.dart';
import 'widgets/mesa_form_dialog.dart';

class TableManagementScreen extends StatefulWidget {
  const TableManagementScreen({super.key});

  @override
  State<TableManagementScreen> createState() => _TableManagementScreenState();
}

class _TableManagementScreenState extends State<TableManagementScreen> {
  List<String> espacios = {'Bar', 'Terraza', 'Salón Principal'}.toList();
  /*SynchronizationResponse? synchronizationResponse;
  final SynchronizationApiService synchronizationApiService =
      SynchronizationApiService();

  Future<void> cargarEspacios() async {
    EspacioDao espacioDao = EspacioDao();
    List<Espacio> listaEspacios = await espacioDao.obtenerEspacios(
      await DBHelper.database,
    );

    setState(() {
      espacios = listaEspacios;
    });
  }

  @override
  void initState() {
    super.initState();
    cargarEspacios();
  }*/

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
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                FilterChip(
                  label: const Text('TODO'),
                  selected: true,
                  onSelected: (bool value) {},
                ),
                const SizedBox(width: 8),
                ...espacios.map((espacio) {
                  return FilterChip(
                    label: Text(espacio),
                    selected: false,
                    onSelected: (bool selected) {},
                  );
                }),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: 10,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text('Mesa ${index + 1}'),
                  subtitle: const Text('Estado: Libre'),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () {
                    // Navegar a la pantalla de detalles de la mesa
                  },
                );
              },
            ),
          ),
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
      onAgregarMesa: () => _abrirFormularioMesa(context),
      onAgregarEspacio: () => _abrirFormularioEspacio(context),
    );
  }

  Future<void> _abrirFormularioEspacio(BuildContext context) async {
    final resultado = await showDialog<EspacioFormResult>(
      context: context,
      builder: (_) => const EspacioFormDialog(),
    );

    if (resultado == null) return;

    setState(() {
      espacios.add(resultado.titulo);
    });

    // TODO: persistir resultado.identificacion y resultado.visibilidad
    // cuando se integre con EspacioDao / SynchronizationApiService.
  }

  Future<void> _abrirFormularioMesa(BuildContext context) async {
    final resultado = await showDialog<MesaFormResult>(
      context: context,
      builder: (_) => MesaFormDialog(espaciosDisponibles: espacios),
    );

    if (resultado == null) return;

    // TODO: persistir la nueva mesa cuando exista el modelo/DAO de Mesa.
  }
}
