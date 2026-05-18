// File: lib/utils/sync_utilities.dart
// ✅ VERSIONE CORRETTA - Classi spostate al top-level

import 'dart:async';
import 'package:flutter/material.dart';

/// Timeout exception personalizzata
class TimeoutException implements Exception {
  final String message;
  
  TimeoutException(this.message);
  
  @override
  String toString() => 'TimeoutException: $message';
}

/// Eccezione personalizzata per sincronizzazione
class SyncException implements Exception {
  final String message;
  final String? operation;
  final dynamic originalError;
  
  SyncException(this.message, {this.operation, this.originalError});
  
  @override
  String toString() {
    String result = 'SyncException: $message';
    if (operation != null) result += ' (operation: $operation)';
    if (originalError != null) result += ' (cause: $originalError)';
    return result;
  }
}

/// Validazione robusta degli input
class InputValidator {
  
  static String? validateFolderName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return 'Il nome non può essere vuoto';
    }
    
    final trimmed = name.trim();
    
    if (trimmed.length > 50) {
      return 'Il nome è troppo lungo (max 50 caratteri)';
    }
    
    if (trimmed.contains(RegExp(r'[<>:"/\\|?*]'))) {
      return 'Il nome contiene caratteri non validi';
    }
    
    if (trimmed.startsWith('.') || trimmed.endsWith('.')) {
      return 'Il nome non può iniziare o finire con un punto';
    }
    
    return null; // Valido
  }
  
  static String? validatePostTitle(String? title) {
    if (title == null || title.trim().isEmpty) {
      return 'Il titolo non può essere vuoto';
    }
    
    final trimmed = title.trim();
    
    if (trimmed.length > 200) {
      return 'Il titolo è troppo lungo (max 200 caratteri)';
    }
    
    return null; // Valido
  }
  
  static String? validateUrl(String? url) {
    if (url == null || url.trim().isEmpty) {
      return 'L\'URL non può essere vuoto';
    }
    
    try {
      final uri = Uri.parse(url.trim());
      if (!uri.hasScheme || !uri.hasAuthority) {
        return 'URL non valido';
      }
      return null; // Valido
    } catch (e) {
      return 'URL non valido: $e';
    }
  }
  
  static List<String> sanitizeTags(List<String> tags) {
    return tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .where((tag) => tag.length <= 30)
        .map((tag) => tag.replaceAll(RegExp(r'[,;]+'), ''))
        .toSet() // Rimuovi duplicati
        .toList();
  }
}

/// Gestione errori con categorizzazione
class ErrorHandler {
  
  static String getErrorMessage(dynamic error) {
    if (error is TimeoutException) {
      return 'Operazione interrotta per timeout. Riprova.';
    }
    
    if (error is FormatException) {
      return 'Formato dati non valido.';
    }
    
    if (error is ArgumentError) {
      return 'Dati inseriti non validi: ${error.message}';
    }
    
    if (error.toString().contains('network') || 
        error.toString().contains('connection')) {
      return 'Errore di rete. Controlla la connessione.';
    }
    
    if (error.toString().contains('permission')) {
      return 'Permessi insufficienti.';
    }
    
    if (error.toString().contains('storage') || 
        error.toString().contains('space')) {
      return 'Spazio insufficiente sul dispositivo.';
    }
    
    // Errore generico
    return 'Si è verificato un errore imprevisto.';
  }
  
  static bool isRetryableError(dynamic error) {
    if (error is TimeoutException) return true;
    
    final errorString = error.toString().toLowerCase();
    
    // Errori di rete sono riprovabili
    if (errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('timeout') ||
        errorString.contains('unreachable')) {
      return true;
    }
    
    // Errori di validazione non sono riprovabili
    if (error is ArgumentError || error is FormatException) {
      return false;
    }
    
    // Default: non riprovabile per sicurezza
    return false;
  }
  
  static void showErrorSnackBar(
    BuildContext context,
    dynamic error, {
    String? customMessage,
  }) {
    final message = customMessage ?? getErrorMessage(error);
    
    
  }
  
  static void showSuccessSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    
  }
}

/// Logger per debug migliorato
class DebugLogger {
  static bool _isEnabled = true;
  
  static void enable() => _isEnabled = true;
  static void disable() => _isEnabled = false;
  
  static void log(String message, {String? tag}) {
    if (!_isEnabled) return;
    
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    final logTag = tag != null ? '[$tag]' : '[DEBUG]';
    print('$timestamp $logTag $message');
  }
  
  static void logStart(String operation) {
    log('=== INIZIO: $operation ===', tag: 'START');
  }
  
  static void logEnd(String operation) {
    log('=== FINE: $operation ===', tag: 'END');
  }
  
  static void logSuccess(String operation) {
    log('✅ $operation completato con successo', tag: 'SUCCESS');
  }
  
  static void logError(String operation, dynamic error) {
    log('❌ $operation fallito: $error', tag: 'ERROR');
  }
  
  static void logWarning(String message) {
    log('⚠️ $message', tag: 'WARNING');
  }
  
  static void logStep(String step, int current, int total) {
    log('Step $current/$total: $step', tag: 'STEP');
  }
}

/// Helper per path cartelle
class PathHelper {
  
  static String buildPath(List<String> pathParts) {
    return pathParts.join(' › ');
  }
  
  static List<String> splitPath(String path) {
    return path.split(' › ').map((part) => part.trim()).toList();
  }
  
  static String getParentPath(String path) {
    final parts = splitPath(path);
    if (parts.length <= 1) return '';
    return buildPath(parts.sublist(0, parts.length - 1));
  }
  
  static String getFinalFolderName(String path) {
    final parts = splitPath(path);
    return parts.isNotEmpty ? parts.last : '';
  }
  
  static int getDepth(String path) {
    return path.isEmpty ? 0 : splitPath(path).length;
  }
  
  static bool isSubpathOf(String childPath, String parentPath) {
    if (parentPath.isEmpty) return true;
    return childPath.startsWith('$parentPath › ');
  }
}

/// Convertitori di colore sicuri
class ColorHelper {
  
  static Color fromHex(String hexString, {Color fallback = Colors.blue}) {
    try {
      if (hexString.isEmpty) return fallback;
      
      String cleanHex = hexString.replaceAll('#', '').replaceAll(' ', '');
      if (cleanHex.length == 6) {
        cleanHex = 'ff$cleanHex'; // Aggiungi alpha
      }
      
      final intValue = int.parse(cleanHex, radix: 16);
      return Color(intValue);
      
    } catch (e) {
      DebugLogger.logWarning('Conversione colore fallita per "$hexString": $e');
      return fallback;
    }
  }
  
  static String toHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }
  
  static List<Color> getRandomColors() {
    return [
      Colors.blue.shade400,
      Colors.green.shade400,
      Colors.orange.shade400,
      Colors.purple.shade400,
      Colors.red.shade400,
      Colors.teal.shade400,
      Colors.indigo.shade400,
      Colors.pink.shade400,
      Colors.amber.shade400,
      Colors.cyan.shade400,
    ];
  }
  
  static Color getRandomColor() {
    final colors = getRandomColors();
    return colors[DateTime.now().millisecondsSinceEpoch % colors.length];
  }
}

/// ✅ Utility class per operazioni di sincronizzazione
class SyncUtilities {
  
  /// Esegue un'operazione con retry automatico
  static Future<T> withRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration baseDelay = const Duration(milliseconds: 500),
    String? operationName,
  }) async {
    int currentRetry = 0;
    Exception? lastException;
    
    while (currentRetry < maxRetries) {
      try {
        if (operationName != null) {
          print('DEBUG: $operationName (tentativo ${currentRetry + 1}/$maxRetries)');
        }
        
        final result = await operation();
        
        if (operationName != null && currentRetry > 0) {
          print('DEBUG: ✅ $operationName riuscito al tentativo ${currentRetry + 1}');
        }
        
        return result;
        
      } catch (e) {
        lastException = e as Exception;
        
        if (operationName != null) {
          print('WARNING: $operationName fallito (tentativo ${currentRetry + 1}): $e');
        }
        
        currentRetry++;
        
        if (currentRetry < maxRetries) {
          final delayMs = baseDelay.inMilliseconds * currentRetry;
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      }
    }
    
    // Se arriva qui, tutti i tentativi sono falliti
    final errorMessage = operationName != null 
        ? '$operationName fallito dopo $maxRetries tentativi'
        : 'Operazione fallita dopo $maxRetries tentativi';
    
    print('ERRORE: $errorMessage');
    throw lastException ?? Exception(errorMessage);
  }

  /// Esegue un'operazione con timeout
  static Future<T> withTimeout<T>(
    Future<T> Function() operation, {
    Duration timeout = const Duration(seconds: 10),
    String? operationName,
  }) async {
    try {
      if (operationName != null) {
        print('DEBUG: $operationName (timeout: ${timeout.inSeconds}s)');
      }
      
      final result = await Future.any([
        operation(),
        Future.delayed(timeout, () => throw TimeoutException(
          operationName != null 
              ? '$operationName timeout dopo ${timeout.inSeconds}s'
              : 'Operazione timeout dopo ${timeout.inSeconds}s'
        )),
      ]);
      
      if (operationName != null) {
        print('DEBUG: ✅ $operationName completato entro timeout');
      }
      
      return result;
      
    } on TimeoutException {
      if (operationName != null) {
        print('TIMEOUT: $operationName interrotto dopo ${timeout.inSeconds} secondi');
      }
      rethrow;
    } catch (e) {
      if (operationName != null) {
        print('ERRORE: $operationName fallito: $e');
      }
      rethrow;
    }
  }

  /// Combina retry e timeout
  static Future<T> withRetryAndTimeout<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration timeout = const Duration(seconds: 10),
    Duration baseDelay = const Duration(milliseconds: 500),
    String? operationName,
  }) async {
    return withRetry(
      () => withTimeout(operation, timeout: timeout, operationName: operationName),
      maxRetries: maxRetries,
      baseDelay: baseDelay,
      operationName: operationName,
    );
  }

  /// Debounce per evitare chiamate multiple rapide
  static Timer? _debounceTimer;
  
  static void debounce(
    Duration duration,
    VoidCallback action, {
    String? actionName,
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(duration, () {
      if (actionName != null) {
        print('DEBUG: Eseguendo azione debounceed: $actionName');
      }
      action();
    });
  }
}