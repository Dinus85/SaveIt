// simple_analytics_service.dart
// ✅ VERSIONE COMPLETA con SharedPreferences e tracking tempo REALE

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:shared_preferences/shared_preferences.dart';

// Eventi semplificati
enum SimpleEventType {
  appOpened,
  folderOpened,
  postViewed,
  searchPerformed,
  folderCreated,
  folderDeleted,
  themeChanged,
}

// Evento semplice
class SimpleEvent {
  final String id;
  final SimpleEventType type;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  SimpleEvent({
    required this.id,
    required this.type,
    required this.timestamp,
    this.data = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'timestamp': timestamp.toIso8601String(),
    'data': data,
  };

  factory SimpleEvent.fromJson(Map<String, dynamic> json) => SimpleEvent(
    id: json['id'],
    type: SimpleEventType.values.firstWhere((e) => e.name == json['type']),
    timestamp: DateTime.parse(json['timestamp']),
    data: Map<String, dynamic>.from(json['data'] ?? {}),
  );
}

// Statistiche semplici
class SimpleStats {
  final int totalAppOpens;
  final int totalFoldersOpened;
  final int totalPostsViewed;
  final int totalSearches;
  final int totalFoldersCreated;
  final Duration totalTimeInApp;
  final Map<String, int> topFolders;
  final Map<String, int> topSocialNetworks;
  final Map<String, int> hourlyUsage;
  final Map<int, int> weeklyUsage; // 1=lunedì, 7=domenica
  final DateTime firstUse;
  final DateTime lastUse;
  final int streakDays;

  SimpleStats({
    required this.totalAppOpens,
    required this.totalFoldersOpened,
    required this.totalPostsViewed,
    required this.totalSearches,
    required this.totalFoldersCreated,
    required this.totalTimeInApp,
    required this.topFolders,
    required this.topSocialNetworks,
    required this.hourlyUsage,
    required this.weeklyUsage,
    required this.firstUse,
    required this.lastUse,
    required this.streakDays,
  });
}

// Service con storage REALE
class SimpleAnalyticsService {
  static final SimpleAnalyticsService _instance = SimpleAnalyticsService._internal();
  factory SimpleAnalyticsService() => _instance;
  SimpleAnalyticsService._internal();

  static const String _eventsKey = 'simple_analytics_events';
  static const String _totalTimeKey = 'total_time_milliseconds';
  static const String _lastSessionEndKey = 'last_session_end_time';
  
  List<SimpleEvent> _events = [];
  DateTime? _sessionStart;
  int _totalTimeMilliseconds = 0; // ✅ TEMPO REALE ACCUMULATO
  bool _isInitialized = false;

  // ✅ Inizializza il servizio CON CARICAMENTO DA STORAGE
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _loadEvents();
    await _loadTotalTime(); // ✅ CARICA TEMPO ACCUMULATO
    _startSession();
    _isInitialized = true;
    
    print('DEBUG: SimpleAnalyticsService inizializzato con ${_events.length} eventi');
    print('DEBUG: Tempo totale accumulato: ${Duration(milliseconds: _totalTimeMilliseconds).inMinutes} minuti');
    // Non bloccante: sincronizza su Firestore in background senza ritardare lo startup
    unawaited(syncAnalyticsSummaryToFirestore());
  }

  // ✅ CARICA EVENTI DA SHARED PREFERENCES
  Future<void> _loadEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final eventsJson = prefs.getStringList(_eventsKey) ?? [];
      
      _events = eventsJson.map((json) {
        try {
          return SimpleEvent.fromJson(jsonDecode(json));
        } catch (e) {
          print('ERRORE: Parsing evento fallito: $e');
          return null;
        }
      }).whereType<SimpleEvent>().toList();
      
      print('DEBUG: Caricati ${_events.length} eventi da storage');
    } catch (e) {
      print('ERRORE: Caricamento eventi analytics fallito: $e');
      _events = [];
    }
  }

  // ✅ CARICA TEMPO TOTALE ACCUMULATO
  Future<void> _loadTotalTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _totalTimeMilliseconds = prefs.getInt(_totalTimeKey) ?? 0;
      print('DEBUG: Tempo totale caricato: ${Duration(milliseconds: _totalTimeMilliseconds).inMinutes}min');
    } catch (e) {
      print('ERRORE: Caricamento tempo totale fallito: $e');
      _totalTimeMilliseconds = 0;
    }
  }

  // ✅ SALVA EVENTI IN SHARED PREFERENCES
  Future<void> _saveEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Mantieni solo ultimi 500 eventi per performance
      final recentEvents = _events.take(500).toList();
      final eventsJson = recentEvents.map((event) => jsonEncode(event.toJson())).toList();
      
      await prefs.setStringList(_eventsKey, eventsJson);
      print('DEBUG: Salvati ${eventsJson.length} eventi in storage');
    } catch (e) {
      print('ERRORE: Salvataggio eventi analytics fallito: $e');
    }
  }

  // ✅ SALVA TEMPO TOTALE ACCUMULATO
  Future<void> _saveTotalTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_totalTimeKey, _totalTimeMilliseconds);
      print('DEBUG: Tempo totale salvato: ${Duration(milliseconds: _totalTimeMilliseconds).inMinutes}min');
    } catch (e) {
      print('ERRORE: Salvataggio tempo totale fallito: $e');
    }
  }

  // ✅ Inizia sessione con tracking TEMPO REALE
  void _startSession() {
    _sessionStart = DateTime.now();
    trackEvent(SimpleEventType.appOpened);
    print('DEBUG: Sessione iniziata: ${_sessionStart}');
  }

  // ✅ Termina sessione e AGGIORNA TEMPO REALE
  Future<void> endSession() async {
    if (_sessionStart != null) {
      final sessionDuration = DateTime.now().difference(_sessionStart!);
      
      // ✅ AGGIUNGI TEMPO REALE DELLA SESSIONE AL TOTALE
      _totalTimeMilliseconds += sessionDuration.inMilliseconds;
      
      print('DEBUG: Sessione terminata - Durata: ${sessionDuration.inMinutes}min ${sessionDuration.inSeconds % 60}s');
      print('DEBUG: Tempo totale accumulato: ${Duration(milliseconds: _totalTimeMilliseconds).inMinutes}min');
      
      // Salva tempo totale
      await _saveTotalTime();
      
      // Salva timestamp fine sessione
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSessionEndKey, DateTime.now().toIso8601String());
      
      _sessionStart = null;
    }
    
    await _saveEvents();
    await syncAnalyticsSummaryToFirestore();
  }

  // Traccia evento generico
  void trackEvent(SimpleEventType type, {Map<String, dynamic>? data}) {
    final event = SimpleEvent(
      id: _generateId(),
      type: type,
      timestamp: DateTime.now(),
      data: data ?? {},
    );
    
    _events.insert(0, event); // Aggiungi in testa (più recente)
    print('Analytics: ${type.name} - ${data ?? {}}');
    
    // Auto-save ogni 5 eventi
    if (_events.length % 5 == 0) {
      _saveEvents();
    }
  }

  // Metodi helper per tracciare eventi specifici
  void trackFolderOpened(String folderName) {
    trackEvent(SimpleEventType.folderOpened, data: {
      'folderName': folderName,
      'hour': DateTime.now().hour,
      'weekday': DateTime.now().weekday,
    });
  }

  void trackPostViewed(String postTitle, String folderName, {String? socialNetwork}) {
    trackEvent(SimpleEventType.postViewed, data: {
      'postTitle': postTitle,
      'folderName': folderName,
      'socialNetwork': socialNetwork,
      'hour': DateTime.now().hour,
      'weekday': DateTime.now().weekday,
    });
  }

  void trackSearchPerformed(String query, int resultCount) {
    if (query.trim().length >= 2) {
      trackEvent(SimpleEventType.searchPerformed, data: {
        'query': query,
        'resultCount': resultCount,
        'queryLength': query.length,
        'hour': DateTime.now().hour,
        'weekday': DateTime.now().weekday,
      });
    }
  }

  void trackFolderCreated(String folderName) {
    trackEvent(SimpleEventType.folderCreated, data: {
      'folderName': folderName,
      'hour': DateTime.now().hour,
      'weekday': DateTime.now().weekday,
    });
  }

  void trackFolderDeleted(String folderName) {
    trackEvent(SimpleEventType.folderDeleted, data: {
      'folderName': folderName,
      'hour': DateTime.now().hour,
      'weekday': DateTime.now().weekday,
    });
  }

  void trackThemeChanged(bool isDark) {
    trackEvent(SimpleEventType.themeChanged, data: {
      'newTheme': isDark ? 'dark' : 'light',
      'hour': DateTime.now().hour,
    });
  }

  // ✅ CALCOLA STATISTICHE CON TEMPO REALE
  SimpleStats calculateStats() {
    if (_events.isEmpty) {
      return SimpleStats(
        totalAppOpens: 0,
        totalFoldersOpened: 0,
        totalPostsViewed: 0,
        totalSearches: 0,
        totalFoldersCreated: 0,
        totalTimeInApp: Duration.zero,
        topFolders: {},
        topSocialNetworks: {},
        hourlyUsage: {},
        weeklyUsage: {},
        firstUse: DateTime.now(),
        lastUse: DateTime.now(),
        streakDays: 0,
      );
    }

    // Conteggi base
    final totalAppOpens = _events.where((e) => e.type == SimpleEventType.appOpened).length;
    final totalFoldersOpened = _events.where((e) => e.type == SimpleEventType.folderOpened).length;
    final totalPostsViewed = _events.where((e) => e.type == SimpleEventType.postViewed).length;
    final totalSearches = _events.where((e) => e.type == SimpleEventType.searchPerformed).length;
    final totalFoldersCreated = _events.where((e) => e.type == SimpleEventType.folderCreated).length;

    // Top folders
    final folderCounts = <String, int>{};
    for (var event in _events.where((e) => e.data.containsKey('folderName'))) {
      final folderName = event.data['folderName'] as String;
      folderCounts[folderName] = (folderCounts[folderName] ?? 0) + 1;
    }

    // Top social networks
    final socialCounts = <String, int>{};
    for (var event in _events.where((e) => e.data.containsKey('socialNetwork'))) {
      final social = event.data['socialNetwork'] as String?;
      if (social != null) {
        socialCounts[social] = (socialCounts[social] ?? 0) + 1;
      }
    }

    // Utilizzo orario
    final hourlyCounts = <String, int>{};
    for (var event in _events.where((e) => e.data.containsKey('hour'))) {
      final hour = event.data['hour'].toString();
      hourlyCounts[hour] = (hourlyCounts[hour] ?? 0) + 1;
    }

    // Utilizzo settimanale
    final weeklyCounts = <int, int>{};
    for (var event in _events.where((e) => e.data.containsKey('weekday'))) {
      final weekday = event.data['weekday'] as int;
      weeklyCounts[weekday] = (weeklyCounts[weekday] ?? 0) + 1;
    }

    // Date - ordina eventi per timestamp
    final sortedEvents = List<SimpleEvent>.from(_events)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final firstUse = sortedEvents.first.timestamp;
    final lastUse = sortedEvents.last.timestamp;

    // Streak giorni
    final streakDays = _calculateSimpleStreak();

    // ✅ TEMPO TOTALE REALE (include sessione corrente se attiva)
    var totalTime = Duration(milliseconds: _totalTimeMilliseconds);
    
    // Se c'è una sessione attiva, aggiungi anche il suo tempo
    if (_sessionStart != null) {
      final currentSessionTime = DateTime.now().difference(_sessionStart!);
      totalTime += currentSessionTime;
      print('DEBUG: Tempo sessione corrente: ${currentSessionTime.inMinutes}min ${currentSessionTime.inSeconds % 60}s');
    }
    
    print('DEBUG: Tempo totale calcolato: ${totalTime.inMinutes}min ${totalTime.inSeconds % 60}s');

    return SimpleStats(
      totalAppOpens: totalAppOpens,
      totalFoldersOpened: totalFoldersOpened,
      totalPostsViewed: totalPostsViewed,
      totalSearches: totalSearches,
      totalFoldersCreated: totalFoldersCreated,
      totalTimeInApp: totalTime, // ✅ TEMPO REALE!
      topFolders: _sortMapByValue(folderCounts),
      topSocialNetworks: _sortMapByValue(socialCounts),
      hourlyUsage: hourlyCounts,
      weeklyUsage: weeklyCounts,
      firstUse: firstUse,
      lastUse: lastUse,
      streakDays: streakDays,
    );
  }

  // Calcola streak semplificato
  int _calculateSimpleStreak() {
    if (_events.isEmpty) return 0;

    final openEvents = _events
        .where((e) => e.type == SimpleEventType.appOpened)
        .map((e) => DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (openEvents.isEmpty) return 0;

    int streak = 1;
    for (int i = 1; i < openEvents.length; i++) {
      if (openEvents[i - 1].difference(openEvents[i]).inDays == 1) {
        streak++;
      } else {
        break;
      }
    }

    return streak;
  }

  // Ordina mappa per valore
  Map<String, int> _sortMapByValue(Map<String, int> map) {
    final sortedEntries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sortedEntries);
  }

  // Genera ID unico
  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString() + 
           Random().nextInt(1000).toString();
  }

  // Pulisci eventi vecchi (mantieni ultimi 60 giorni)
  Future<void> cleanOldEvents() async {
    final cutoffDate = DateTime.now().subtract(Duration(days: 60));
    final oldCount = _events.length;
    _events.removeWhere((event) => event.timestamp.isBefore(cutoffDate));
    
    if (oldCount != _events.length) {
      await _saveEvents();
      print('DEBUG: Puliti ${oldCount - _events.length} eventi più vecchi di 60 giorni');
    }
  }

  // ✅ Reset completo (cancella anche tempo accumulato)
  Future<void> clearAllData() async {
    _events.clear();
    _totalTimeMilliseconds = 0;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_eventsKey);
    await prefs.remove(_totalTimeKey);
    await prefs.remove(_lastSessionEndKey);
    
    print('DEBUG: Tutti i dati analytics cancellati (incluso tempo accumulato)');
  }

  // Export dati
  String exportData() {
    return jsonEncode({
      'exportDate': DateTime.now().toIso8601String(),
      'events': _events.map((e) => e.toJson()).toList(),
      'totalTimeMinutes': Duration(milliseconds: _totalTimeMilliseconds).inMinutes,
      'stats': _eventsToStatsJson(),
    });
  }

  Future<void> syncAnalyticsSummaryToFirestore() async {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;

    try {
      final stats = calculateStats();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .collection('analytics')
          .doc('summary')
          .set({
        'totalAppOpens': stats.totalAppOpens,
        'totalFoldersOpened': stats.totalFoldersOpened,
        'totalPostsViewed': stats.totalPostsViewed,
        'totalSearches': stats.totalSearches,
        'totalFoldersCreated': stats.totalFoldersCreated,
        'totalTimeMinutes': stats.totalTimeInApp.inMinutes,
        'streakDays': stats.streakDays,
        'firstUse': stats.firstUse.toIso8601String(),
        'lastUse': stats.lastUse.toIso8601String(),
        'topFolders': stats.topFolders,
        'topSocialNetworks': stats.topSocialNetworks,
        'hourlyUsage': stats.hourlyUsage,
        'weeklyUsage': stats.weeklyUsage.map(
          (key, value) => MapEntry(key.toString(), value),
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('ERRORE: Sync statistiche analytics su Firestore fallito: $e');
    }
  }

  Map<String, dynamic> _eventsToStatsJson() {
    final stats = calculateStats();
    return {
      'totalAppOpens': stats.totalAppOpens,
      'totalFoldersOpened': stats.totalFoldersOpened,
      'totalPostsViewed': stats.totalPostsViewed,
      'totalSearches': stats.totalSearches,
      'totalFoldersCreated': stats.totalFoldersCreated,
      'totalTimeInApp': stats.totalTimeInApp.inMinutes,
      'topFolders': stats.topFolders,
      'topSocialNetworks': stats.topSocialNetworks,
      'streakDays': stats.streakDays,
      'firstUse': stats.firstUse.toIso8601String(),
      'lastUse': stats.lastUse.toIso8601String(),
    };
  }

  // Getter per debug
  int get totalEvents => _events.length;
  bool get isInitialized => _isInitialized;
  Duration get totalTimeAccumulated => Duration(milliseconds: _totalTimeMilliseconds);
}