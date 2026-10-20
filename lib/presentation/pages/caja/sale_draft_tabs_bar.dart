import 'package:flutter/material.dart';

import 'sale_draft_tabs_controller.dart';

class SaleDraftTabsBar extends StatefulWidget {
  const SaleDraftTabsBar({
    required this.controller,
    required this.enabled,
    required this.onSelect,
    required this.onAdd,
    super.key,
  });

  final SaleDraftTabsController controller;
  final bool enabled;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  @override
  State<SaleDraftTabsBar> createState() => _SaleDraftTabsBarState();
}

class _SaleDraftTabsBarState extends State<SaleDraftTabsBar> {
  final _tabKeys = <int, GlobalKey>{};
  int _visibleSelection = -1;

  void _revealSelection() {
    final index = widget.controller.selectedIndex;
    if (index < 0 || index == _visibleSelection) return;
    _visibleSelection = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tabContext = _tabKeys[index]?.currentContext;
      if (tabContext != null) {
        Scrollable.ensureVisible(
          tabContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 150),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      _revealSelection();
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < widget.controller.length; i++)
                      KeyedSubtree(
                        key: _tabKeys.putIfAbsent(i, () => GlobalKey()),
                        child: ChoiceChip(
                          key: ValueKey('sale-tab-$i'),
                          label: Text('Venta ${i + 1}'),
                          selected: widget.controller.selectedIndex == i,
                          onSelected: widget.enabled
                              ? (_) => widget.onSelect(i)
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Agregar venta',
              onPressed: widget.enabled && widget.controller.ready
                  ? widget.onAdd
                  : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      );
    },
  );
}
