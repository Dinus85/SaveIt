// File: lib/services/folder_service_models.dart
// Modelli di supporto per FolderService

import 'package:flutter/material.dart';
import 'package:savein/models/folder.dart';

import 'package:savein/models.dart'; // Importa MockPost e MockFolder da qui

// ============================================================================
// ENUMS E MODELLI DI STATO
// ============================================================================

/// Stato di salute del servizio
enum ServiceHealthStatus {
  healthy,
  degraded,
  offline,
  error,
  authenticating,
  unknown
}

/// Metriche di salute del servizio
class ServiceHealthMetrics {
  final ServiceHealthStatus status;
  final DateTime lastUpdate;
  final String? errorMessage;
  final Map<String, dynamic> metrics;
  final String? userContext;

  ServiceHealthMetrics({
    required this.status,
    required this.lastUpdate,
    this.errorMessage,
    this.metrics = const {},
    this.userContext,
  });

  Map<String, dynamic> toMap() {
    return {
      'status': status.toString(),
      'lastUpdate': lastUpdate.toIso8601String(),
      'errorMessage': errorMessage,
      'metrics': metrics,
      'userContext': userContext,
    };
  }
}

// ============================================================================
// MODELLI BUSINESS LOGIC
// ============================================================================

/// Risultato di ricerca unificato
class SearchResult {
  final String type;
  final String title;
  final String subtitle;
  final Color? color;
  final MockFolder? folder;
  final MockPost? post;
  final List<String> matchedTerms;

  SearchResult({
    required this.type,
    required this.title,
    required this.subtitle,
    this.color,
    this.folder,
    this.post,
    this.matchedTerms = const [],
  });
}

// NOTA: MockPost viene importato da '../models.dart'
// Non ridefinirlo qui per evitare conflitti

/// Cartella in formato piatto per UI gerarchiche
class FlatFolder {
  final MockFolder folder;
  final String fullPath;
  final int level;
  final bool hasChildren;

  FlatFolder({
    required this.folder,
    required this.fullPath,
    required this.level,
    required this.hasChildren,
  });
  
  @override
  String toString() {
    return 'FlatFolder(name: ${folder.name}, path: $fullPath, level: $level, hasChildren: $hasChildren)';
  }
}