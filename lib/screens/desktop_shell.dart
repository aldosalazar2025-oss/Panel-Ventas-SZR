import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'ajustes_screen.dart';
import 'historial_screen.dart';
import 'inventario_screen.dart';
import 'pos_desktop_screen.dart';

/// Ventana principal de Panel SZR Ventas: menú lateral + pantalla activa.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  int _pagina = 0;

  Widget _pantalla() {
    switch (_pagina) {
      case 0:
        return const PosDesktopScreen();
      case 1:
        return const InventarioScreen();
      case 2:
        return const HistorialScreen();
      default:
        return const AjustesScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: AppTheme.bgWhite,
            selectedIndex: _pagina,
            onDestinationSelected: (i) => setState(() => _pagina = i),
            labelType: NavigationRailLabelType.all,
            indicatorColor: AppTheme.bgGrey,
            selectedIconTheme: const IconThemeData(color: AppTheme.primary),
            selectedLabelTextStyle: const TextStyle(
              color: AppTheme.primary,
              fontWeight: FontWeight.bold,
            ),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Image.asset(
                'assets/logo.png',
                width: 84,
                height: 84,
                filterQuality: FilterQuality.medium,
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.point_of_sale_outlined),
                selectedIcon: Icon(Icons.point_of_sale),
                label: Text('Vender'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2),
                label: Text('Inventario'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: Text('Historial'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Ajustes'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          // Se recrea al cambiar de pestaña para mostrar datos al día.
          Expanded(child: KeyedSubtree(key: ValueKey(_pagina), child: _pantalla())),
        ],
      ),
    );
  }
}
