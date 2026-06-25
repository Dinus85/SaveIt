// advanced_analytics_service.dart
// ✅ VERSIONE COMPLETA con SharedPreferences e statistiche avanzate REALI

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/simple_analytics_service.dart';
import 'advanced_analytics_models.dart';

class AdvancedAnalyticsService {
  static final AdvancedAnalyticsService _instance =
      AdvancedAnalyticsService._internal();
  factory AdvancedAnalyticsService() => _instance;
  AdvancedAnalyticsService._internal();

  // Storage keys
  static const String _advancedEventsKey = 'advanced_analytics_events';
  static const String _sessionsKey = 'user_sessions';
  static const String _contentInteractionsKey = 'content_interactions';
  static const String _cachedStatsKey = 'cached_advanced_stats';

  // Data in memoria
  List<AdvancedEvent> _events = [];
  List<SessionData> _sessions = [];
  Map<String, ContentInteraction> _contentInteractions = {};
  AdvancedAnalyticsData? _cachedStats;

  // Stato sessione corrente
  SessionData? _currentSession;
  DateTime? _lastActionTime;
  Timer? _inactivityTimer;
  Map<String, DateTime> _actionStartTimes = {};

  bool _isInitialized = false;
  final SimpleAnalyticsService _baseAnalytics = SimpleAnalyticsService();

  // Configuration
  static const Duration _inactivityThreshold = Duration(minutes: 2);
  static const Duration _sessionTimeout = Duration(minutes: 30);
  static const int _maxEventsInMemory = 1000;

  /// ✅ Inizializza il service avanzato CON CARICAMENTO DA STORAGE
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _baseAnalytics.initialize();
    await _loadAdvancedData(); // ✅ CARICA DA SHARED PREFERENCES
    _startSmartSession();

    _isInitialized = true;
    print(
        'DEBUG: AdvancedAnalyticsService inizializzato con ${_events.length} eventi avanzati');
  }

  /// ✅ CARICA DATI DA SHARED PREFERENCES
  Future<void> _loadAdvancedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Carica eventi avanzati
      final eventsJson = prefs.getStringList(_advancedEventsKey) ?? [];
      _events = eventsJson
          .map((json) {
            try {
              return AdvancedEvent.fromJson(jsonDecode(json));
            } catch (e) {
              print('ERRORE: Parsing evento avanzato fallito: $e');
              return null;
            }
          })
          .whereType<AdvancedEvent>()
          .toList();

      // Carica sessioni
      final sessionsJson = prefs.getStringList(_sessionsKey) ?? [];
      _sessions = sessionsJson
          .map((json) {
            try {
              return SessionData.fromJson(jsonDecode(json));
            } catch (e) {
              print('ERRORE: Parsing sessione fallita: $e');
              return null;
            }
          })
          .whereType<SessionData>()
          .toList();

      // Carica interazioni contenuti
      final interactionsJson = prefs.getString(_contentInteractionsKey);
      if (interactionsJson != null) {
        try {
          final decoded = jsonDecode(interactionsJson) as Map<String, dynamic>;
          _contentInteractions = {};
          decoded.forEach((k, v) {
            try {
              _contentInteractions[k] = ContentInteraction.fromJson(v);
            } catch (e) {
              print('ERRORE: Parsing interaction fallita per $k: $e');
            }
          });
        } catch (e) {
          print('ERRORE: Parsing interactions fallito: $e');
          _contentInteractions = {};
        }
      }

      // Carica stats cache
      final cachedStatsJson = prefs.getString(_cachedStatsKey);
      if (cachedStatsJson != null) {
        try {
          _cachedStats =
              AdvancedAnalyticsData.fromJson(jsonDecode(cachedStatsJson));
        } catch (e) {
          print('ERRORE: Parsing cached stats fallito: $e');
          _cachedStats = null;
        }
      }

      print(
          'DEBUG: Dati avanzati caricati - ${_events.length} eventi, ${_sessions.length} sessioni, ${_contentInteractions.length} interactions');
    } catch (e) {
      print('ERRORE: Caricamento dati avanzati fallito: $e');
      _resetToEmpty();
    }
  }

  /// ✅ SALVA DATI IN SHARED PREFERENCES
  Future<void> _saveAdvancedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Salva eventi (mantieni solo gli ultimi per performance)
      final recentEvents = _events.take(_maxEventsInMemory).toList();
      final eventsJson =
          recentEvents.map((event) => jsonEncode(event.toJson())).toList();
      await prefs.setStringList(_advancedEventsKey, eventsJson);

      // Salva sessioni (mantieni ultime 50)
      final recentSessions = _sessions.take(50).toList();
      final sessionsJson = recentSessions
          .map((session) => jsonEncode(session.toJson()))
          .toList();
      await prefs.setStringList(_sessionsKey, sessionsJson);

      // Salva interazioni contenuti
      final interactionsJson = jsonEncode(
          _contentInteractions.map((k, v) => MapEntry(k, v.toJson())));
      await prefs.setString(_contentInteractionsKey, interactionsJson);

      // Salva stats cache se disponibili
      if (_cachedStats != null) {
        await prefs.setString(
            _cachedStatsKey, jsonEncode(_cachedStats!.toJson()));
      }

      print(
          'DEBUG: Dati avanzati salvati - ${recentEvents.length} eventi, ${recentSessions.length} sessioni');
    } catch (e) {
      print('ERRORE: Salvataggio dati avanzati fallito: $e');
    }
  }

  /// Resetta a stato vuoto
  void _resetToEmpty() {
    _events = [];
    _sessions = [];
    _contentInteractions = {};
    _cachedStats = null;
  }

  Future<void> clearLocalAnalyticsData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_advancedEventsKey);
      await prefs.remove(_sessionsKey);
      await prefs.remove(_contentInteractionsKey);
      await prefs.remove(_cachedStatsKey);
    } catch (e) {
      debugPrint('ERRORE: Pulizia analytics avanzata locale fallita: $e');
    }
    _resetToEmpty();
    _currentSession = null;
    _lastActionTime = null;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    _actionStartTimes = {};
    _isInitialized = false;
  }

  /// Avvia sessione intelligente
  void _startSmartSession() {
    final sessionId = _generateId();
    final now = DateTime.now();

    _currentSession = SessionData(
      sessionId: sessionId,
      startTime: now,
      activeDuration: Duration.zero,
      totalDuration: Duration.zero,
      actionsPerformed: [],
      folderInteractions: {},
      contentInteractions: {},
      timePerAction: {},
    );

    trackAdvancedEvent(
      AdvancedEventType.sessionStarted,
      properties: {
        'sessionId': sessionId,
        'startTime': now.toIso8601String(),
        'devicePlatform': 'web',
      },
    );

    _startInactivityMonitoring();
    print('DEBUG: Sessione avanzata avviata: $sessionId');
  }

  /// Termina sessione corrente
  Future<void> endSmartSession() async {
    if (_currentSession == null) return;

    final now = DateTime.now();
    final session = _currentSession!.copyWith(
      endTime: now,
      totalDuration: now.difference(_currentSession!.startTime),
    );

    final wasProductive = _calculateSessionProductivity(session);
    final finalSession = SessionData(
      sessionId: session.sessionId,
      startTime: session.startTime,
      endTime: now,
      activeDuration: session.activeDuration,
      totalDuration: session.totalDuration,
      actionsPerformed: session.actionsPerformed,
      folderInteractions: session.folderInteractions,
      contentInteractions: session.contentInteractions,
      timePerAction: session.timePerAction,
      backgroundSwitches: session.backgroundSwitches,
      wasProductive: wasProductive,
    );

    _sessions.insert(0, finalSession);

    trackAdvancedEvent(
      AdvancedEventType.sessionEnded,
      properties: {
        'sessionId': session.sessionId,
        'duration': session.totalDuration.inSeconds,
        'activeDuration': session.activeDuration.inSeconds,
        'actionsCount': session.actionsPerformed.length,
        'wasProductive': wasProductive,
        'productivityScore': finalSession.productivityScore,
      },
    );

    _currentSession = null;
    _stopInactivityMonitoring();
    await _saveAdvancedData();

    print(
        'DEBUG: Sessione terminata: ${session.sessionId} (${session.totalDuration.inMinutes}min, produttiva: $wasProductive)');
  }

  /// Calcola se una sessione è produttiva
  bool _calculateSessionProductivity(SessionData session) {
    if (session.totalDuration.inSeconds < 30) return false;
    if (session.actionsPerformed.length < 3) return false;
    if (session.productivityScore < 0.3) return false;
    return true;
  }

  /// Monitora inattività per pausare sessione
  void _startInactivityMonitoring() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (_lastActionTime != null) {
        final inactiveTime = DateTime.now().difference(_lastActionTime!);
        if (inactiveTime > _inactivityThreshold) {
          trackAdvancedEvent(AdvancedEventType.inactivityDetected, properties: {
            'inactiveDuration': inactiveTime.inSeconds,
          });
        }
      }
    });
  }

  /// Ferma monitoraggio inattività
  void _stopInactivityMonitoring() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  /// Traccia evento avanzato
  void trackAdvancedEvent(
    AdvancedEventType type, {
    Map<String, dynamic>? properties,
    Map<String, dynamic>? context,
    Duration? actionDuration,
    String? previousEventId,
  }) {
    final now = DateTime.now();
    final event = AdvancedEvent(
      id: _generateId(),
      type: type,
      timestamp: now,
      properties: properties ?? {},
      context: {
        'sessionId': _currentSession?.sessionId,
        'platform': 'web',
        'appVersion': '1.0.0',
        ...?context,
      },
      actionDuration: actionDuration,
      previousEventId: previousEventId,
    );

    _events.insert(0, event);
    _updateCurrentSession(type, properties ?? {}, actionDuration);
    _lastActionTime = now;

    if (_events.length > _maxEventsInMemory) {
      _events = _events.take(_maxEventsInMemory).toList();
    }

    print('AdvancedAnalytics: ${type.name} - ${properties ?? {}}');

    // ✅ FIX: Salva ogni 3 eventi per ridurre perdita dati
    if (_events.length % 3 == 0) {
      _saveAdvancedData();
    }
  }

  /// Aggiorna sessione corrente con nuova azione
  void _updateCurrentSession(AdvancedEventType type,
      Map<String, dynamic> properties, Duration? actionDuration) {
    if (_currentSession == null) return;

    final actionName = type.name;
    final updatedActions = List<String>.from(_currentSession!.actionsPerformed)
      ..add(actionName);

    var updatedActiveDuration = _currentSession!.activeDuration;
    if (actionDuration != null) {
      updatedActiveDuration += actionDuration;
    }

    final updatedFolderInteractions =
        Map<String, int>.from(_currentSession!.folderInteractions);
    if (properties.containsKey('folderId')) {
      final folderId = properties['folderId'] as String;
      updatedFolderInteractions[folderId] =
          (updatedFolderInteractions[folderId] ?? 0) + 1;
    }

    final updatedContentInteractions =
        Map<String, int>.from(_currentSession!.contentInteractions);
    if (properties.containsKey('postId')) {
      final postId = properties['postId'] as String;
      updatedContentInteractions[postId] =
          (updatedContentInteractions[postId] ?? 0) + 1;
    }

    final updatedTimePerAction =
        Map<String, Duration>.from(_currentSession!.timePerAction);
    if (actionDuration != null) {
      final currentAvg = updatedTimePerAction[actionName] ?? Duration.zero;
      final actionCount = updatedActions.where((a) => a == actionName).length;
      final newAvg = Duration(
          milliseconds: ((currentAvg.inMilliseconds * (actionCount - 1)) +
                  actionDuration.inMilliseconds) ~/
              actionCount);
      updatedTimePerAction[actionName] = newAvg;
    }

    _currentSession = SessionData(
      sessionId: _currentSession!.sessionId,
      startTime: _currentSession!.startTime,
      endTime: _currentSession!.endTime,
      activeDuration: updatedActiveDuration,
      totalDuration: DateTime.now().difference(_currentSession!.startTime),
      actionsPerformed: updatedActions,
      folderInteractions: updatedFolderInteractions,
      contentInteractions: updatedContentInteractions,
      timePerAction: updatedTimePerAction,
      backgroundSwitches: _currentSession!.backgroundSwitches,
      wasProductive: _currentSession!.wasProductive,
    );
  }

  /// Traccia interazione con contenuto
  void trackContentInteraction(
    String postId,
    String postTitle,
    String postUrl, {
    String? folderPath,
    List<String>? tags,
    String? socialNetwork,
    bool isNewSave = false,
    bool isOpening = false,
    Duration? viewDuration,
  }) {
    final now = DateTime.now();
    final existing = _contentInteractions[postId];

    if (existing == null && isNewSave) {
      _contentInteractions[postId] = ContentInteraction(
        postId: postId,
        postTitle: postTitle,
        postUrl: postUrl,
        folderPath: folderPath,
        savedDate: now,
        tags: tags ?? [],
        socialNetwork: socialNetwork,
      );

      trackAdvancedEvent(AdvancedEventType.contentRevisited, properties: {
        'postId': postId,
        'postTitle': postTitle,
        'folderPath': folderPath,
        'socialNetwork': socialNetwork,
        'action': 'saved',
      });
    } else if (existing != null && isOpening) {
      final isFirstOpen = existing.wasNeverOpened;
      final updatedOpenTimes = List<DateTime>.from(existing.openTimes)
        ..add(now);
      final updatedViewDurations = List<Duration>.from(existing.viewDurations);
      if (viewDuration != null) {
        updatedViewDurations.add(viewDuration);
      }

      _contentInteractions[postId] = ContentInteraction(
        postId: existing.postId,
        postTitle: existing.postTitle,
        postUrl: existing.postUrl,
        folderPath: existing.folderPath,
        savedDate: existing.savedDate,
        firstOpened: existing.firstOpened ?? now,
        lastOpened: now,
        openCount: existing.openCount + 1,
        openTimes: updatedOpenTimes,
        viewDurations: updatedViewDurations,
        wasNeverOpened: false,
        isHighEngagement: (existing.openCount + 1) >= 3,
        tags: existing.tags,
        socialNetwork: existing.socialNetwork,
      );

      trackAdvancedEvent(
        isFirstOpen
            ? AdvancedEventType.contentRevisited
            : AdvancedEventType.contentRevisited,
        properties: {
          'postId': postId,
          'postTitle': postTitle,
          'openCount': existing.openCount + 1,
          'isFirstOpen': isFirstOpen,
          'timeToFirstOpen':
              isFirstOpen ? now.difference(existing.savedDate).inMinutes : null,
          'viewDuration': viewDuration?.inSeconds,
        },
      );
    }
  }

  /// ✅ Rilevamento contenuti duplicati
  void detectDuplicateContent(String url, String title) {
    final similarContent = _contentInteractions.values.where((content) {
      final urlSimilarity = _calculateSimilarity(url, content.postUrl);
      final titleSimilarity = _calculateSimilarity(title, content.postTitle);
      return urlSimilarity > 0.8 || titleSimilarity > 0.9;
    }).toList();

    if (similarContent.isNotEmpty) {
      trackAdvancedEvent(AdvancedEventType.duplicateContentSaved, properties: {
        'newUrl': url,
        'newTitle': title,
        'similarContentCount': similarContent.length,
        'similarUrls': similarContent.map((c) => c.postUrl).take(3).toList(),
      });
    }
  }

  /// ✅ Calcola similarità tra due stringhe
  double _calculateSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final longer = a.length > b.length ? a : b;
    final shorter = a.length > b.length ? b : a;

    if (longer.length == 0) return 1.0;

    final editDistance = _levenshteinDistance(longer, shorter);
    return (longer.length - editDistance) / longer.length;
  }

  /// ✅ Calcola distanza di Levenshtein
  int _levenshteinDistance(String a, String b) {
    final matrix =
        List.generate(a.length + 1, (i) => List.filled(b.length + 1, 0));

    for (int i = 0; i <= a.length; i++) matrix[i][0] = i;
    for (int j = 0; j <= b.length; j++) matrix[0][j] = j;

    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce(math.min);
      }
    }

    return matrix[a.length][b.length];
  }

  /// Calcola statistiche comportamentali
  BehavioralStats calculateBehavioralStats() {
    if (_sessions.isEmpty) {
      return BehavioralStats(
        avgSessionTime: Duration.zero,
        revisitationRate: 0.0,
        abandonmentRate: 0.0,
        avgSaveToOpenTime: Duration.zero,
        avgActionInterval: Duration.zero,
        actionEfficiency: {},
        usagePatterns: [],
        consistencyScore: 0.0,
        preferredActions: {},
        batchActionsDetected: 0,
      );
    }

    final totalSessionTime = _sessions.fold<Duration>(
        Duration.zero, (sum, s) => sum + s.sessionLength);
    final avgSessionTime = Duration(
        milliseconds: totalSessionTime.inMilliseconds ~/ _sessions.length);

    final totalContent = _contentInteractions.length;
    final revisitedContent =
        _contentInteractions.values.where((c) => !c.wasNeverOpened).length;
    final revisitationRate =
        totalContent > 0 ? revisitedContent / totalContent : 0.0;
    final abandonmentRate = 1.0 - revisitationRate;

    final saveToOpenTimes = _contentInteractions.values
        .where((c) => c.timeToFirstOpen != null)
        .map((c) => c.timeToFirstOpen!)
        .toList();
    final avgSaveToOpenTime = saveToOpenTimes.isNotEmpty
        ? Duration(
            milliseconds: saveToOpenTimes.fold<int>(
                    0, (sum, d) => sum + d.inMilliseconds) ~/
                saveToOpenTimes.length)
        : Duration.zero;

    var actionIntervals = <Duration>[];
    for (final session in _sessions) {
      if (session.actionsPerformed.length > 1) {
        final intervalMs = session.sessionLength.inMilliseconds ~/
            session.actionsPerformed.length;
        actionIntervals.add(Duration(milliseconds: intervalMs));
      }
    }
    final avgActionInterval = actionIntervals.isNotEmpty
        ? Duration(
            milliseconds: actionIntervals.fold<int>(
                    0, (sum, d) => sum + d.inMilliseconds) ~/
                actionIntervals.length)
        : Duration.zero;

    final actionEfficiency = <String, double>{};
    final allActions = _sessions.expand((s) => s.actionsPerformed).toList();
    final actionCounts = <String, int>{};
    for (final action in allActions) {
      actionCounts[action] = (actionCounts[action] ?? 0) + 1;
    }

    for (final action in actionCounts.keys) {
      final count = actionCounts[action]!;
      final efficiency = count / allActions.length;
      actionEfficiency[action] = efficiency;
    }

    final usagePatterns = <String>[];
    if (avgSessionTime.inMinutes > 5) usagePatterns.add('Sessioni lunghe');
    if (revisitationRate > 0.7) usagePatterns.add('Alta revisitazione');
    if (actionCounts.containsKey('folderCreated') &&
        actionCounts['folderCreated']! > 5) {
      usagePatterns.add('Organizzatore attivo');
    }

    final sessionDurations =
        _sessions.map((s) => s.sessionLength.inMinutes).toList();
    final meanDuration = sessionDurations.isEmpty
        ? 0.0
        : sessionDurations.reduce((a, b) => a + b) / sessionDurations.length;
    final variance = sessionDurations.isEmpty
        ? 0.0
        : sessionDurations.fold<double>(
                0.0, (sum, d) => sum + math.pow(d - meanDuration, 2)) /
            sessionDurations.length;
    final consistencyScore = variance > 0
        ? math.max(0.0, 1.0 - (math.sqrt(variance) / meanDuration))
        : 1.0;

    final preferredActions = Map<String, int>.from(actionCounts);
    final batchSessions = _sessions
        .where((s) =>
            s.actionsPerformed.length >= 5 && s.sessionLength.inMinutes <= 10)
        .length;

    return BehavioralStats(
      avgSessionTime: avgSessionTime,
      revisitationRate: revisitationRate,
      abandonmentRate: abandonmentRate,
      avgSaveToOpenTime: avgSaveToOpenTime,
      avgActionInterval: avgActionInterval,
      actionEfficiency: actionEfficiency,
      usagePatterns: usagePatterns,
      consistencyScore: consistencyScore.clamp(0.0, 1.0),
      preferredActions: preferredActions,
      batchActionsDetected: batchSessions,
    );
  }

  /// Calcola micro-timing stats
  MicroTimingStats calculateMicroTimingStats() {
    final hourlyPreciseUsage = <String, int>{};
    final peakUsageWindows = <String, double>{};
    final weekdayVsWeekend = <String, int>{'weekday': 0, 'weekend': 0};
    final monthlyPatterns = <String, int>{};
    final seasonalTrends = <String, int>{};

    for (final event in _events) {
      final timestamp = event.timestamp;

      final hour = timestamp.hour;
      final minute = timestamp.minute;
      final window = minute < 15
          ? '00-15'
          : minute < 30
              ? '15-30'
              : minute < 45
                  ? '30-45'
                  : '45-60';
      final preciseSlot = '$hour:$window';
      hourlyPreciseUsage[preciseSlot] =
          (hourlyPreciseUsage[preciseSlot] ?? 0) + 1;

      final isWeekend = timestamp.weekday >= 6;
      weekdayVsWeekend[isWeekend ? 'weekend' : 'weekday'] =
          (weekdayVsWeekend[isWeekend ? 'weekend' : 'weekday'] ?? 0) + 1;

      final monthKey =
          '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}';
      monthlyPatterns[monthKey] = (monthlyPatterns[monthKey] ?? 0) + 1;

      final season = _getSeason(timestamp.month);
      seasonalTrends[season] = (seasonalTrends[season] ?? 0) + 1;
    }

    final sortedUsage = hourlyPreciseUsage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (int i = 0; i < math.min(5, sortedUsage.length); i++) {
      final entry = sortedUsage[i];
      final score = entry.value /
          (hourlyPreciseUsage.values.isNotEmpty
              ? hourlyPreciseUsage.values.reduce(math.max)
              : 1);
      peakUsageWindows[entry.key] = score;
    }

    final timeToFirstActions = _sessions
        .where((s) => s.actionsPerformed.isNotEmpty)
        .map((s) => Duration(seconds: 30))
        .toList();
    final avgTimeToFirstAction = timeToFirstActions.isNotEmpty
        ? Duration(
            milliseconds: timeToFirstActions.fold<int>(
                    0, (sum, d) => sum + d.inMilliseconds) ~/
                timeToFirstActions.length)
        : Duration.zero;

    final detectedSchedules = <String>[];
    final peakHours = peakUsageWindows.keys.map((k) => k.split(':')[0]).toSet();
    if (peakHours.length <= 2) {
      detectedSchedules.add('Utilizzo concentrato: ${peakHours.join(', ')}');
    }
    if (weekdayVsWeekend['weekend']! > weekdayVsWeekend['weekday']!) {
      detectedSchedules.add('Utente weekend');
    }

    final totalEvents = _events.length;
    final uniqueTimeSlots = hourlyPreciseUsage.keys.length;
    final temporalConsistency =
        totalEvents > 0 ? (uniqueTimeSlots / (24 * 4)).clamp(0.0, 1.0) : 0.0;

    return MicroTimingStats(
      hourlyPreciseUsage: hourlyPreciseUsage,
      peakUsageWindows: peakUsageWindows,
      weekdayVsWeekend: weekdayVsWeekend,
      monthlyPatterns: monthlyPatterns,
      seasonalTrends: seasonalTrends,
      detectedSchedules: detectedSchedules,
      avgTimeToFirstAction: avgTimeToFirstAction,
      actionSequenceTiming: {},
      temporalConsistency: temporalConsistency,
    );
  }

  String _getSeason(int month) {
    switch (month) {
      case 12:
      case 1:
      case 2:
        return 'winter';
      case 3:
      case 4:
      case 5:
        return 'spring';
      case 6:
      case 7:
      case 8:
        return 'summer';
      case 9:
      case 10:
      case 11:
        return 'autumn';
      default:
        return 'unknown';
    }
  }

  /// Calcola metriche qualità contenuti
  ContentQualityMetrics calculateContentQualityMetrics() {
    final totalContent = _contentInteractions.length;
    final neverOpenedContent =
        _contentInteractions.values.where((c) => c.wasNeverOpened).length;
    final highEngagementContent =
        _contentInteractions.values.where((c) => c.isHighEngagement).length;

    var duplicateContent = 0;
    final urlsChecked = <String>{};
    for (final interaction in _contentInteractions.values) {
      final domain = _extractDomain(interaction.postUrl);
      if (urlsChecked.contains(domain)) {
        duplicateContent++;
      } else {
        urlsChecked.add(domain);
      }
    }

    final contentEfficiencyScore = totalContent > 0
        ? (totalContent - neverOpenedContent) / totalContent
        : 0.0;

    final socialNetworkDistribution = <String, int>{};
    final socialNetworkEngagement = <String, double>{};

    for (final interaction in _contentInteractions.values) {
      final network = interaction.socialNetwork ?? 'unknown';
      socialNetworkDistribution[network] =
          (socialNetworkDistribution[network] ?? 0) + 1;

      final currentEngagement = socialNetworkEngagement[network] ?? 0.0;
      final count = socialNetworkDistribution[network]!;
      socialNetworkEngagement[network] =
          (currentEngagement * (count - 1) + interaction.engagementScore) /
              count;
    }

    final recommendedCleanup = _contentInteractions.values
        .where((c) =>
            c.wasNeverOpened &&
            DateTime.now().difference(c.savedDate).inDays > 30)
        .map((c) => c.postId)
        .take(10)
        .toList();

    final oldContent = _contentInteractions.values
        .where((c) => DateTime.now().difference(c.savedDate).inDays > 90);
    final retainedOldContent = oldContent.where((c) => !c.wasNeverOpened);
    final contentRetentionRate = oldContent.isNotEmpty
        ? retainedOldContent.length / oldContent.length
        : 0.0;

    return ContentQualityMetrics(
      totalContent: totalContent,
      duplicateContent: duplicateContent,
      neverOpenedContent: neverOpenedContent,
      highEngagementContent: highEngagementContent,
      contentEfficiencyScore: contentEfficiencyScore,
      socialNetworkDistribution: socialNetworkDistribution,
      socialNetworkEngagement: socialNetworkEngagement,
      recommendedCleanup: recommendedCleanup,
      contentRetentionRate: contentRetentionRate,
    );
  }

  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.toLowerCase();
    } catch (e) {
      return 'unknown';
    }
  }

  /// Genera insight automatici
  List<AnalyticsInsight> generateInsights() {
    final insights = <AnalyticsInsight>[];
    final behavioralStats = calculateBehavioralStats();
    final contentQuality = calculateContentQualityMetrics();
    final microTiming = calculateMicroTimingStats();

    if (contentQuality.neverOpenedContent > 0) {
      final abandonmentRate =
          contentQuality.neverOpenedContent / contentQuality.totalContent;
      if (abandonmentRate > 0.5) {
        insights.add(AnalyticsInsight(
          id: _generateId(),
          type: 'content',
          title: 'Alto tasso di abbandono contenuti',
          description:
              'Il ${(abandonmentRate * 100).toInt()}% dei contenuti salvati non viene mai aperto.',
          recommendation:
              'Considera di rivedere i criteri di salvataggio o organizzare meglio i contenuti per trovarli facilmente.',
          confidence: 0.9,
          supportingData: {
            'abandonmentRate': abandonmentRate,
            'neverOpenedCount': contentQuality.neverOpenedContent,
            'totalContent': contentQuality.totalContent,
          },
          generatedAt: DateTime.now(),
          isActionable: true,
        ));
      }
    }

    final weekendUsage = microTiming.weekdayVsWeekend['weekend'] ?? 0;
    final weekdayUsage = microTiming.weekdayVsWeekend['weekday'] ?? 0;
    if (weekendUsage > weekdayUsage * 2) {
      insights.add(AnalyticsInsight(
        id: _generateId(),
        type: 'behavior',
        title: 'Utilizzo prevalentemente weekend',
        description:
            'Usi SaveIn! principalmente nei weekend (${((weekendUsage / (weekendUsage + weekdayUsage)) * 100).toInt()}% del tempo).',
        recommendation:
            'Considera di impostare promemoria per utilizzare SaveIn! anche durante la settimana.',
        confidence: 0.8,
        supportingData: {
          'weekendUsage': weekendUsage,
          'weekdayUsage': weekdayUsage,
          'weekendPercentage': weekendUsage / (weekendUsage + weekdayUsage),
        },
        generatedAt: DateTime.now(),
        isActionable: true,
      ));
    }

    if (behavioralStats.avgSessionTime.inMinutes < 2) {
      insights.add(AnalyticsInsight(
        id: _generateId(),
        type: 'productivity',
        title: 'Sessioni molto brevi',
        description:
            'Le tue sessioni durano in media ${behavioralStats.avgSessionTime.inSeconds} secondi.',
        recommendation:
            'Prova a dedicare più tempo per organizzare e rivedere i contenuti salvati.',
        confidence: 0.7,
        supportingData: {
          'avgSessionSeconds': behavioralStats.avgSessionTime.inSeconds,
          'totalSessions': _sessions.length,
        },
        generatedAt: DateTime.now(),
        isActionable: true,
      ));
    }

    return insights;
  }

  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        math.Random().nextInt(1000).toString();
  }

  /// Pulisce dati vecchi per performance
  Future<void> cleanOldData({int maxDays = 90}) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: maxDays));

    _events.removeWhere((event) => event.timestamp.isBefore(cutoffDate));
    _sessions.removeWhere((session) => session.startTime.isBefore(cutoffDate));

    _contentInteractions.removeWhere((key, interaction) =>
        interaction.savedDate.isBefore(cutoffDate) &&
        interaction.wasNeverOpened);

    await _saveAdvancedData();
    print(
        'DEBUG: Pulizia dati completata - eventi: ${_events.length}, sessioni: ${_sessions.length}');
  }

  /// Calcola e cache tutte le statistiche avanzate
  Future<AdvancedAnalyticsData> calculateFullAdvancedStats() async {
    final orgMetrics = OrganizationalMetrics(
      avgFolderDepth: 0.0,
      maxFolderDepth: 0,
      totalFolders: 0,
      flatFolders: 0,
      nestedFolders: 0,
      emptyFolders: 0,
      foldersUtilizationRate: 0.0,
      depthDistribution: {},
      underutilizedFolders: [],
      overutilizedFolders: [],
      organizationalEfficiency: 0.0,
    );

    _cachedStats = AdvancedAnalyticsData(
      sessions: List.from(_sessions),
      contentInteractions: _contentInteractions.values.toList(),
      organizationalMetrics: orgMetrics,
      behavioralStats: calculateBehavioralStats(),
      microTimingStats: calculateMicroTimingStats(),
      contentQualityMetrics: calculateContentQualityMetrics(),
      insights: generateInsights(),
      lastCalculated: DateTime.now(),
    );

    await _saveAdvancedData();
    return _cachedStats!;
  }

  AdvancedAnalyticsData? get cachedStats => _cachedStats;

  /// ✅ Reset completo
  Future<void> clearAllAdvancedData() async {
    _events.clear();
    _sessions.clear();
    _contentInteractions.clear();
    _cachedStats = null;
    _currentSession = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_advancedEventsKey);
    await prefs.remove(_sessionsKey);
    await prefs.remove(_contentInteractionsKey);
    await prefs.remove(_cachedStatsKey);

    print('DEBUG: Tutti i dati avanzati cancellati');
  }

  String exportAdvancedData() {
    return jsonEncode({
      'exportDate': DateTime.now().toIso8601String(),
      'version': '1.0.0',
      'events': _events.map((e) => e.toJson()).toList(),
      'sessions': _sessions.map((s) => s.toJson()).toList(),
      'contentInteractions':
          _contentInteractions.map((k, v) => MapEntry(k, v.toJson())),
      'cachedStats': _cachedStats?.toJson(),
    });
  }

  int get totalAdvancedEvents => _events.length;
  int get totalSessions => _sessions.length;
  int get totalContentInteractions => _contentInteractions.length;
  bool get isInitialized => _isInitialized;
}
