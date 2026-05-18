import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';

// Utility class per validazioni
class Validators {
  // Valida se una stringa è un URL valido
  static bool isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  // Valida se una stringa contiene almeno un URL
  static bool containsUrl(String text) {
    final urlRegex = RegExp(
      r'https?://[^\s<>"]+|www\.[^\s<>"]+',
      caseSensitive: false,
    );
    return urlRegex.hasMatch(text);
  }

  // Estrae tutti gli URL da un testo
  static List<String> extractUrls(String text) {
    final urlRegex = RegExp(
      r'https?://[^\s<>"]+|www\.[^\s<>"]+',
      caseSensitive: false,
    );
    return urlRegex.allMatches(text).map((match) => match.group(0)!).toList();
  }

  // Valida nome cartella
  static bool isValidFolderName(String name) {
    return name.trim().isNotEmpty && 
           name.length <= 50 && 
           !name.contains(RegExp(r'[<>:"/\\|?*]'));
  }

  // Valida tag
  static bool isValidTag(String tag) {
    return tag.trim().isNotEmpty && 
           tag.length <= 30 && 
           !tag.contains(' ');
  }
}

// Utility class per formatters
class Formatters {
  // Formatta data in modo user-friendly
  static String formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Ora';
        }
        return '${difference.inMinutes}m fa';
      }
      return '${difference.inHours}h fa';
    } else if (difference.inDays == 1) {
      return 'Ieri';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} giorni fa';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks settiman${weeks == 1 ? 'a' : 'e'} fa';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months mes${months == 1 ? 'e' : 'i'} fa';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years ann${years == 1 ? 'o' : 'i'} fa';
    }
  }

  // Formatta data completa
  static String formatFullDate(DateTime date) {
    const months = [
      'Gennaio', 'Febbraio', 'Marzo', 'Aprile', 'Maggio', 'Giugno',
      'Luglio', 'Agosto', 'Settembre', 'Ottobre', 'Novembre', 'Dicembre'
    ];
    
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  // Formatta numero di post
  static String formatPostCount(int count) {
    if (count == 0) return 'Vuota';
    if (count == 1) return '1 Post';
    return '$count Post';
  }

  // Formatta dimensione file
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  // Formatta testo per preview
  static String formatPreviewText(String text, {int maxLength = 150}) {
    if (text.isEmpty) return 'Nessuna descrizione disponibile';
    
    text = text.trim();
    if (text.length <= maxLength) return text;
    
    // Trova l'ultimo spazio prima del limite
    int cutIndex = maxLength;
    for (int i = maxLength - 1; i >= maxLength * 0.8; i--) {
      if (text[i] == ' ') {
        cutIndex = i;
        break;
      }
    }
    
    return '${text.substring(0, cutIndex)}...';
  }
}

// Utility class per colori
class ColorUtils {
  // Colori predefiniti per le cartelle
  static const List<String> folderColors = [
    '#FF5722', // Deep Orange
    '#FF9800', // Orange
    '#FFC107', // Amber
    '#FFEB3B', // Yellow
    '#CDDC39', // Lime
    '#8BC34A', // Light Green
    '#4CAF50', // Green
    '#009688', // Teal
    '#00BCD4', // Cyan
    '#03A9F4', // Light Blue
    '#2196F3', // Blue
    '#3F51B5', // Indigo
    '#673AB7', // Deep Purple
    '#9C27B0', // Purple
    '#E91E63', // Pink
    '#F44336', // Red
  ];

  // Ottieni colore casuale
  static String getRandomColor() {
    final random = Random();
    return folderColors[random.nextInt(folderColors.length)];
  }

  // Converti hex a Color
  static Color hexToColor(String hex) {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  }

  // Converti Color a hex
  static String colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  // Ottieni colore di contrasto
  static Color getContrastColor(Color color) {
    final luminance = color.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  // Verifica se il colore è scuro
  static bool isDarkColor(Color color) {
    return color.computeLuminance() < 0.5;
  }
}

// Utility class per navigazione e URL
class NavigationUtils {
  // Apri URL nel browser
  static Future<bool> openUrl(String url) async {
    try {
      // Assicurati che l'URL abbia uno schema
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }
      
      final uri = Uri.parse(url);
      
      if (await canLaunchUrl(uri)) {
        return await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      }
      return false;
    } catch (e) {
      print('Errore nell\'apertura dell\'URL: $e');
      return false;
    }
  }

  // Condividi testo
  static Future<void> shareText(String text) async {
    // TODO: Implementare condivisione nativa
    // Per ora solo stampa
    print('Condivisione: $text');
  }

  // Naviga con animazione custom
  static Future<T?> navigateWithSlideTransition<T>(
    BuildContext context,
    Widget page, {
    SlideDirection direction = SlideDirection.fromRight,
  }) {
    Offset beginOffset;
    switch (direction) {
      case SlideDirection.fromLeft:
        beginOffset = Offset(-1.0, 0.0);
        break;
      case SlideDirection.fromRight:
        beginOffset = Offset(1.0, 0.0);
        break;
      case SlideDirection.fromTop:
        beginOffset = Offset(0.0, -1.0);
        break;
      case SlideDirection.fromBottom:
        beginOffset = Offset(0.0, 1.0);
        break;
    }

    return Navigator.push<T>(
      context,
      PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: beginOffset,
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            )),
            child: child,
          );
        },
        transitionDuration: Duration(milliseconds: 300),
      ),
    );
  }
}

enum SlideDirection { fromLeft, fromRight, fromTop, fromBottom }

// Utility class per storage e cache
class CacheUtils {
  static const int maxCacheSize = 100 * 1024 * 1024; // 100MB
  
  // Calcola dimensione cache (mock)
  static Future<int> getCacheSize() async {
    // TODO: Implementare calcolo reale
    return Random().nextInt(maxCacheSize);
  }

  // Pulisci cache (mock)
  static Future<void> clearCache() async {
    // TODO: Implementare pulizia cache
    await Future.delayed(Duration(seconds: 1));
  }
}

// Utility class per debugging
class DebugUtils {
  static bool _isDebugMode = false;

  static void enableDebug() {
    _isDebugMode = true;
  }

  static void disableDebug() {
    _isDebugMode = false;
  }

  static void log(String message, [String? tag]) {
    if (_isDebugMode) {
      final timestamp = DateTime.now().toIso8601String();
      final tagPrefix = tag != null ? '[$tag] ' : '';
      print('$timestamp $tagPrefix$message');
    }
  }

  static void logError(String error, [StackTrace? stackTrace]) {
    if (_isDebugMode) {
      log('ERROR: $error', 'ERROR');
      if (stackTrace != null) {
        print(stackTrace);
      }
    }
  }
}

// Utility class per performance
class PerformanceUtils {
  static final Map<String, DateTime> _timers = {};

  // Inizia timer
  static void startTimer(String name) {
    _timers[name] = DateTime.now();
  }

  // Ferma timer e stampa risultato
  static void stopTimer(String name) {
    final start = _timers[name];
    if (start != null) {
      final duration = DateTime.now().difference(start);
      DebugUtils.log('Timer $name: ${duration.inMilliseconds}ms', 'PERF');
      _timers.remove(name);
    }
  }

  // Misura prestazioni di una funzione
  static Future<T> measureAsync<T>(
    String name,
    Future<T> Function() function,
  ) async {
    startTimer(name);
    try {
      final result = await function();
      stopTimer(name);
      return result;
    } catch (e) {
      stopTimer(name);
      rethrow;
    }
  }
}

// Utility class per testi
class TextUtils {
  // Normalizza testo per ricerca
  static String normalizeForSearch(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[ñ]'), 'n')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // Evidenzia testo nella ricerca
  static List<TextSpan> highlightSearchText(
    String text,
    String query, {
    TextStyle? normalStyle,
    TextStyle? highlightStyle,
  }) {
    if (query.isEmpty) {
      return [TextSpan(text: text, style: normalStyle)];
    }

    final spans = <TextSpan>[];
    final normalizedText = text.toLowerCase();
    final normalizedQuery = query.toLowerCase();
    
    int start = 0;
    int index = normalizedText.indexOf(normalizedQuery, start);
    
    while (index != -1) {
      // Aggiungi testo prima del match
      if (index > start) {
        spans.add(TextSpan(
          text: text.substring(start, index),
          style: normalStyle,
        ));
      }
      
      // Aggiungi testo evidenziato
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: highlightStyle ?? TextStyle(
          backgroundColor: Colors.yellow,
          color: Colors.black,
        ),
      ));
      
      start = index + query.length;
      index = normalizedText.indexOf(normalizedQuery, start);
    }
    
    // Aggiungi testo rimanente
    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: normalStyle,
      ));
    }
    
    return spans;
  }

  // Genera abbreviazione
  static String generateAbbreviation(String text, {int maxLength = 2}) {
    final words = text.split(' ').where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return '';
    
    if (words.length == 1) {
      return words[0].substring(0, min(maxLength, words[0].length)).toUpperCase();
    }
    
    return words
        .take(maxLength)
        .map((word) => word[0].toUpperCase())
        .join('');
  }
}

// Extension per DateTime
extension DateTimeExtensions on DateTime {
  bool isSameDay(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }

  bool isToday() {
    return isSameDay(DateTime.now());
  }

  bool isYesterday() {
    final yesterday = DateTime.now().subtract(Duration(days: 1));
    return isSameDay(yesterday);
  }

  String toFormattedString() {
    return Formatters.formatDate(this);
  }
}

// Extension per String
extension StringExtensions on String {
  bool get isValidUrl => Validators.isValidUrl(this);
  bool get containsUrl => Validators.containsUrl(this);
  List<String> get extractedUrls => Validators.extractUrls(this);
  
  String get normalized => TextUtils.normalizeForSearch(this);
  String get abbreviation => TextUtils.generateAbbreviation(this);
  
  Color get hexColor => ColorUtils.hexToColor(this);
}