import 'package:flutter/material.dart';

/// Logo SaveIn! sempre visibile in cima alle pagine secondarie, con il
/// titolo della pagina subito sotto. Usare con
/// `AppBar(toolbarHeight: SaveInPageTitle.toolbarHeight, ...)`.
class SaveInPageTitle extends StatelessWidget {
  const SaveInPageTitle({super.key, required this.title});

  static const double logoHeight = 36;
  static const double toolbarHeight = 104;

  final Widget title;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset(
          'assets/icon/SaveIn!.png',
          height: logoHeight,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: title,
        ),
      ],
    );
  }
}
