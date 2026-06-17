import 'package:flutter/material.dart';
import 'package:pos_flutter/presentation/pages/gestion_mesa/table_management.dart';

class MenuLateral extends StatelessWidget {
  const MenuLateral({super.key});

  Widget _buildBadge(int count) {
    return count > 0
        ? Container(
            padding: EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
            ),
            child: Text(
              count.toString(),
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          )
        : SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Encabezado
          Container(
            color: Colors.blue,
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.white,
                      child: Text("CM", style: TextStyle(color: Colors.black)),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "CERVECERIA MAESTRA Y Taproom",
                            style: TextStyle(color: Colors.white),
                          ),
                          Text(
                            "+524341548804",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.edit, color: Colors.white),
                  ],
                ),
                SizedBox(height: 10),
                Container(
                  color: Colors.purple,
                  padding: EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Icon(Icons.star, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "PREMIUM\nUsted es nuestro Usuario Premium",
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      Icon(Icons.expand_more, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Usuario
          ListTile(
            title: Text("BENJAMÍN ALVARADO GONZÁLEZ (staff)"),
            subtitle: Text("orejonnar@gmail.com"),
            trailing: Text(
              "EDITAR PERFIL",
              style: TextStyle(color: Colors.blue, fontSize: 12),
            ),
          ),
          // Botones
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    child: Text("CAMBIAR DE NEGOCIO"),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: Text("CREAR NEGOCIO"),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Gestión",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          // Opciones del menú
          ListTile(
            leading: Icon(Icons.chat),
            title: Text("Chat de ayuda"),
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.inventory),
            title: Text("Gestión de inventarios"),
            trailing: _buildBadge(329),
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.money_off),
            title: Text("Agregar gasto"),
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.receipt_long),
            title: Text("Recibos"),
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.people),
            title: Text("Gestión de clientess"),
            trailing: _buildBadge(35),
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.table_chart),
            title: Text("Gestión de la mesa"),
            trailing: _buildBadge(19),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TableManagementScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.shopping_bag),
            title: Text("ShopFront"),
            trailing: _buildBadge(0),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
