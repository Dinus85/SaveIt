import 'package:flutter/material.dart';
import '../utils/constants.dart';

// Mock classes per la demo web
class MockFolder {
  String? id; // 🆕 ID reale dal database (opzionale per retrocompatibilità)
  String name;
  String count;
  Color color;
  int level;
  List<MockFolder> children;
  MockFolder? parent;
  bool isSpecial;
  MockFolder? originalFolder; // Per i risultati di ricerca
  bool isShared; // 🆕 NUOVO: Indica se la cartella è stata condivisa

  MockFolder({
    this.id,
    required this.name,
    required this.count,
    required this.color,
    required this.level,
    this.children = const [],
    this.parent,
    this.isSpecial = false,
    this.originalFolder,
    this.isShared = false,
  }) {
    if (children.isEmpty) {
      this.children = <MockFolder>[];
    }
  }

  bool get canHaveSubfolders => !isSpecial && AppConstants.canHaveSubfolders(level);  
  
  int get totalSubfolders {
    int total = children.length;
    for (var child in children) {
      total += child.totalSubfolders;
    }
    return total;
  }
}