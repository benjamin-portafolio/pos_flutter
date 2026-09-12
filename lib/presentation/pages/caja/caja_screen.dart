import 'package:flutter/material.dart';

import '../../widgets/article_search_bar.dart';

class CajaScreen extends StatelessWidget {
  const CajaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Column(
        children: [
          ArticleSearchBar(showQuickAdd: false),
          Expanded(child: Center(child: Text('Caja abierta'))),
        ],
      ),
    );
  }
}
