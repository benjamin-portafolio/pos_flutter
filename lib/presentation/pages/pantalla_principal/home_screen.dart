import 'package:flutter/material.dart';
import 'package:pos_flutter/presentation/pages/articulos/articles_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/caja_screen.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/menu_lateral.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 2;

  late final List<Widget> _screens = [
    const Center(child: Text('Informes')),
    const Center(child: Text('Hoy')),
    CajaScreen(onOpenCaja: () => _onTabTapped(2)),
    ArticlesScreen(onOpenCaja: () => _onTabTapped(2)),
  ];

  void _onTabTapped(int index) {
    if (index == 4) return;

    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    //return Scaffold(body: Center(child: Text('Hello World!')));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentIndex == 3 ? 'Artículos' : 'CERVECERIA MAESTRA Y Ta...',
        ),
        actions: [
          IconButton(icon: Icon(Icons.person_add), onPressed: () {}),
          IconButton(icon: Icon(Icons.phone), onPressed: () {}),
        ],
      ),
      drawer: MenuLateral(),
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blue,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Informes',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.attach_money), label: 'Hoy'),
          BottomNavigationBarItem(
            icon: Icon(Icons.point_of_sale),
            label: 'Caja',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Artículos'),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'Más'),
        ],
      ),
    );
  }
}
