import 'package:flutter/material.dart';
import '../utils/theme_helpers.dart';

class CustomBottomNavigationBar extends StatelessWidget {
  final bool isDarkTheme;
  final VoidCallback onHomeTap;
  final VoidCallback onAddTap;
  final VoidCallback onAccountTap;
  final bool isHomeActive;
  final bool isAccountActive;

  const CustomBottomNavigationBar({
    Key? key,
    required this.isDarkTheme,
    required this.onHomeTap,
    required this.onAddTap,
    required this.onAccountTap,
    this.isHomeActive = false,
    this.isAccountActive = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeColors = ThemeHelpers.getThemeColors(isDarkTheme);
    
    return Container(
      color: themeColors.bottomBarColor,
      padding: EdgeInsets.only(
        top: 16,
        bottom: 16 + MediaQuery.of(context).padding.bottom, // ✅ GESTITO QUI
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            onPressed: onHomeTap,
            icon: Icon(
              Icons.home,
              color: isHomeActive ? Colors.blue : themeColors.iconColor,
              size: 28,
            ),
          ),
          FloatingActionButton(
            onPressed: onAddTap,
            backgroundColor: Colors.white,
            heroTag: "custom_bottom_nav_fab_${DateTime.now().millisecondsSinceEpoch}",
            child: Icon(Icons.add, color: Colors.black, size: 28),
            mini: false,
          ),
          IconButton(
            onPressed: onAccountTap,
            icon: Icon(
              Icons.person,
              color: isAccountActive ? Colors.blue : themeColors.iconColor,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }
}

// Widget per ModalBottomSheet con safe area automatico
class SafeModalBottomSheet extends StatelessWidget {
  final Widget child;
  
  const SafeModalBottomSheet({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom, // ✅ GESTITO QUI
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}