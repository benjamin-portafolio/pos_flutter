import 'dart:convert';

import 'package:flutter/material.dart';
/*import 'package:punto_venta/data/local/dao/espacio_dao.dart';
import 'package:punto_venta/data/local/db_helper.dart';
import 'package:punto_venta/data/models/espacio_model.dart';
import 'package:punto_venta/data/models/synchronization/synchronization_response.dart';
import 'package:punto_venta/data/remote/synchronization/synchronization_api_service.dart';
import 'package:punto_venta/presentation/pages/alta_espacios/alta_espacios_screen.dart';
import 'package:punto_venta/presentation/pages/pruebas_screen.dart';
import 'package:web_socket_channel/web_socket_channel.dart';*/

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
  // late PusherChannelsFlutter pusher;

  Future<void> cargarEspacios() async {
    EspacioDao espacioDao = EspacioDao();
    List<Espacio> listaEspacios = await espacioDao.obtenerEspacios(
      await DBHelper.database,
    );

    setState(() {
      espacios = listaEspacios;
    });

    // print("ejemplo de primer espacio: ${espacios[0].nombre}");
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
                SizedBox(width: 8),
                ...espacios.map((espacio) {
                  return FilterChip(
                    label: Text(espacio),
                    selected: false,
                    onSelected: (bool selected) {
                      /*setState(() {
                          if (selected) {
                            selectedUsuarios.add(usuario);
                          } else {
                            selectedUsuarios.remove(usuario);
                          }
                        });*/
                    },
                    //   avatar: CircleAvatar(child: Text(usuario.nombre[0])),
                  );
                  SizedBox(width: 8);
                }),
              ],
            ),
          ),

          /*Wrap(
            spacing: 8.0,
            children: [
              FilterChip(
                label: const Text('TODO'),
                selected: true,
                onSelected: (bool value) {},
              ),
              ...espacios.map((espacio) {
                return FilterChip(
                  label: Text(espacio),
                  // selected: selectedUsuarios.contains(usuario),
                  onSelected: (bool selected) {
                    /*setState(() {
                          if (selected) {
                            selectedUsuarios.add(usuario);
                          } else {
                            selectedUsuarios.remove(usuario);
                          }
                        });*/
                  },
                  //   avatar: CircleAvatar(child: Text(usuario.nombre[0])),
                );
              }),
            ],
          ),*/
          Expanded(
            child: ListView.builder(
              itemCount: 10,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text('Mesa ${index + 1}'),
                  subtitle: Text('Estado: Libre'),
                  trailing: Icon(Icons.arrow_forward),
                  onTap: () {
                    // Navegar a la pantalla de detalles de la mesa
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
