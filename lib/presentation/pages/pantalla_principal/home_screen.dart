import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:pos_flutter/presentation/pages/articulos/articles_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/caja_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_clientes/clientes_screen.dart';
import 'package:pos_flutter/presentation/pages/informes/reports_screen.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/menu_lateral.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 2;
  bool _navigating = false;
  bool _restoreAfterMenu = false;
  int? _menuReaderGeneration;
  final _caja = GlobalKey<CajaScreenState>();
  final _scaffold = GlobalKey<ScaffoldState>();

  late final List<Widget> _screens = [
    const ReportsScreen(),
    const Center(child: Text('Hoy')),
    CajaScreen(key: _caja, onOpenCaja: () => _onTabTapped(2)),
    ArticlesScreen(onOpenCaja: () => _onTabTapped(2)),
  ];

  Future<bool> _prepareNavigation() async {
    if (_navigating) return false;
    _navigating = true;
    try {
      final allowed = await _caja.currentState?.prepareToLeave() ?? true;
      return mounted && allowed;
    } finally {
      _navigating = false;
    }
  }

  Future<void> _onTabTapped(int index) async {
    if (index == _currentIndex || !await _prepareNavigation()) return;
    if (!mounted) return;
    if (index == 4) {
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute(builder: (_) => const ClientesScreen()));
      return;
    }
    setState(() => _currentIndex = index);
  }

  Future<void> _openMenu() async {
    final restore = _caja.currentState?.isReaderEnabled == true;
    final generation = _caja.currentState?.readerInterruptionGeneration;
    if (await _prepareNavigation()) {
      _restoreAfterMenu = restore;
      _menuReaderGeneration = generation;
      _scaffold.currentState?.openDrawer();
    }
  }

  Future<bool> _beforeMenuNavigate() async {
    final allowed = await _prepareNavigation();
    if (allowed) _restoreAfterMenu = false;
    return allowed;
  }

  void _drawerChanged(bool open) {
    if (!open && _restoreAfterMenu) {
      _restoreAfterMenu = false;
      _caja.currentState?.restoreReader(_menuReaderGeneration);
    }
  }

  Future<void> _leave() async {
    if (await _prepareNavigation() && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop:
        defaultTargetPlatform != TargetPlatform.macOS &&
        defaultTargetPlatform != TargetPlatform.windows,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_leave());
    },
    child: Scaffold(
      key: _scaffold,
      appBar: AppBar(
        title: Text(_currentIndex == 3 ? 'Artículos' : 'PASTOR'),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
          icon: const Icon(Icons.menu),
          onPressed: _openMenu,
        ),
        actions: [
          IconButton(icon: const Icon(Icons.person_add), onPressed: () {}),
          IconButton(icon: const Icon(Icons.phone), onPressed: () {}),
        ],
      ),
      // El botón espera el drenaje antes de exponer operaciones del menú.
      drawerEnableOpenDragGesture: false,
      onDrawerChanged: _drawerChanged,
      drawer: MenuLateral(
        beforeNavigate: _beforeMenuNavigate,
        onOpenCaja: () {
          if (mounted) _onTabTapped(2);
        },
      ),
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
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Clientes'),
        ],
      ),
    ),
  );
}
