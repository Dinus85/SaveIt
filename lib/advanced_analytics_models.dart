// advanced_analytics_models.dart
// Modelli avanzati per statistiche comportamentali e analisi approfondite

import 'dart:convert';
import 'package:flutter/foundation.dart';

// Estende gli eventi base con tracking avanzato
enum AdvancedEventType {
  // Sessioni intelligenti
  sessionStarted,
  sessionEnded,
  actionPerformed,
  inactivityDetected,
  
  // Interazioni contenuti
  contentRevisited,
  contentNeverOpened,
  duplicateContentSaved,
  contentEngagementHigh,
  contentEngagementLow,
  
  // Struttura organizzativa
  folderStructureChanged,
  folderDepthIncreased,
  postMovedBetweenFolders,
  unusedFolderDetected,
  
  // Gestione tag
  tagAdded,
  tagRemoved,
  tagPatternDetected,
  
  // Micro-timing
  preciseActionTiming,
  rapidActionSequence,
  hesitationDetected,
  
  // Pattern comportamentali
  usagePatternChanged,
  peakUsageDetected,
  batchSavingDetected,
  organizationalEfficiencyChanged,
}

// Evento avanzato con timing preciso e contesto
class AdvancedEvent {
  final String id;
  final AdvancedEventType type;
  final DateTime timestamp;
  final Map<String, dynamic> properties;
  final Map<String, dynamic> context; // Contesto aggiuntivo (sessione, device, etc.)
  final Duration? actionDuration; // Durata azione se applicabile
  final String? previousEventId; // Collegamento eventi in sequenza

  AdvancedEvent({
    required this.id,
    required this.type,
    required this.timestamp,
    this.properties = const {},
    this.context = const {},
    this.actionDuration,
    this.previousEventId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'timestamp': timestamp.toIso8601String(),
    'properties': properties,
    'context': context,
    'actionDuration': actionDuration?.inMilliseconds,
    'previousEventId': previousEventId,
  };

  factory AdvancedEvent.fromJson(Map<String, dynamic> json) => AdvancedEvent(
    id: json['id'],
    type: AdvancedEventType.values.firstWhere((e) => e.name == json['type']),
    timestamp: DateTime.parse(json['timestamp']),
    properties: Map<String, dynamic>.from(json['properties'] ?? {}),
    context: Map<String, dynamic>.from(json['context'] ?? {}),
    actionDuration: json['actionDuration'] != null 
        ? Duration(milliseconds: json['actionDuration']) 
        : null,
    previousEventId: json['previousEventId'],
  );
}

// Dati sessione utente intelligenti
class SessionData {
  final String sessionId;
  final DateTime startTime;
  final DateTime? endTime;
  final Duration activeDuration; // Tempo effettivamente attivo
  final Duration totalDuration; // Tempo totale dall'apertura
  final List<String> actionsPerformed;
  final Map<String, int> folderInteractions; // folderId -> count
  final Map<String, int> contentInteractions; // postId -> count
  final Map<String, Duration> timePerAction; // action -> avg duration
  final int backgroundSwitches; // Numero volte app in background
  final bool wasProductive; // Sessione considerata produttiva

  SessionData({
    required this.sessionId,
    required this.startTime,
    this.endTime,
    required this.activeDuration,
    required this.totalDuration,
    required this.actionsPerformed,
    required this.folderInteractions,
    required this.contentInteractions,
    required this.timePerAction,
    this.backgroundSwitches = 0,
    this.wasProductive = false,
  });

  Duration get sessionLength => endTime != null 
      ? endTime!.difference(startTime) 
      : DateTime.now().difference(startTime);

  double get productivityScore => activeDuration.inSeconds / totalDuration.inSeconds;

  // ✅ AGGIUNTO: Metodo copyWith necessario per AdvancedAnalyticsService
  SessionData copyWith({
    String? sessionId,
    DateTime? startTime,
    DateTime? endTime,
    Duration? activeDuration,
    Duration? totalDuration,
    List<String>? actionsPerformed,
    Map<String, int>? folderInteractions,
    Map<String, int>? contentInteractions,
    Map<String, Duration>? timePerAction,
    int? backgroundSwitches,
    bool? wasProductive,
  }) {
    return SessionData(
      sessionId: sessionId ?? this.sessionId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      activeDuration: activeDuration ?? this.activeDuration,
      totalDuration: totalDuration ?? this.totalDuration,
      actionsPerformed: actionsPerformed ?? this.actionsPerformed,
      folderInteractions: folderInteractions ?? this.folderInteractions,
      contentInteractions: contentInteractions ?? this.contentInteractions,
      timePerAction: timePerAction ?? this.timePerAction,
      backgroundSwitches: backgroundSwitches ?? this.backgroundSwitches,
      wasProductive: wasProductive ?? this.wasProductive,
    );
  }

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'activeDuration': activeDuration.inMilliseconds,
    'totalDuration': totalDuration.inMilliseconds,
    'actionsPerformed': actionsPerformed,
    'folderInteractions': folderInteractions,
    'contentInteractions': contentInteractions,
    'timePerAction': timePerAction.map((k, v) => MapEntry(k, v.inMilliseconds)),
    'backgroundSwitches': backgroundSwitches,
    'wasProductive': wasProductive,
  };

  factory SessionData.fromJson(Map<String, dynamic> json) => SessionData(
    sessionId: json['sessionId'],
    startTime: DateTime.parse(json['startTime']),
    endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
    activeDuration: Duration(milliseconds: json['activeDuration']),
    totalDuration: Duration(milliseconds: json['totalDuration']),
    actionsPerformed: List<String>.from(json['actionsPerformed']),
    folderInteractions: Map<String, int>.from(json['folderInteractions']),
    contentInteractions: Map<String, int>.from(json['contentInteractions']),
    timePerAction: Map<String, Duration>.from(
      json['timePerAction'].map((k, v) => MapEntry(k, Duration(milliseconds: v)))
    ),
    backgroundSwitches: json['backgroundSwitches'] ?? 0,
    wasProductive: json['wasProductive'] ?? false,
  );
}

// Interazione contenuto dettagliata
class ContentInteraction {
  final String postId;
  final String postTitle;
  final String postUrl;
  final String? folderPath;
  final DateTime savedDate;
  final DateTime? firstOpened;
  final DateTime? lastOpened;
  final int openCount;
  final List<DateTime> openTimes;
  final List<Duration> viewDurations; // Tempo speso per ogni visualizzazione
  final bool wasNeverOpened;
  final bool isHighEngagement; // > 3 aperture o > 30s totali
  final List<String> tags;
  final String? socialNetwork; // Dominio di origine

  ContentInteraction({
    required this.postId,
    required this.postTitle,
    required this.postUrl,
    this.folderPath,
    required this.savedDate,
    this.firstOpened,
    this.lastOpened,
    this.openCount = 0,
    this.openTimes = const [],
    this.viewDurations = const [],
    this.wasNeverOpened = true,
    this.isHighEngagement = false,
    this.tags = const [],
    this.socialNetwork,
  });

  Duration get totalViewTime => viewDurations.isEmpty 
      ? Duration.zero 
      : viewDurations.reduce((a, b) => a + b);

  Duration get avgViewTime => viewDurations.isEmpty 
      ? Duration.zero 
      : Duration(milliseconds: totalViewTime.inMilliseconds ~/ viewDurations.length);

  Duration? get timeToFirstOpen => firstOpened != null 
      ? firstOpened!.difference(savedDate) 
      : null;

  Duration? get timeSinceLastOpen => lastOpened != null 
      ? DateTime.now().difference(lastOpened!) 
      : null;

  double get engagementScore {
    if (wasNeverOpened) return 0.0;
    final openScore = (openCount / 10.0).clamp(0.0, 1.0); // Max 10 aperture = score 1.0
    final timeScore = (totalViewTime.inSeconds / 300.0).clamp(0.0, 1.0); // Max 5min = score 1.0
    return (openScore + timeScore) / 2.0;
  }

  Map<String, dynamic> toJson() => {
    'postId': postId,
    'postTitle': postTitle,
    'postUrl': postUrl,
    'folderPath': folderPath,
    'savedDate': savedDate.toIso8601String(),
    'firstOpened': firstOpened?.toIso8601String(),
    'lastOpened': lastOpened?.toIso8601String(),
    'openCount': openCount,
    'openTimes': openTimes.map((t) => t.toIso8601String()).toList(),
    'viewDurations': viewDurations.map((d) => d.inMilliseconds).toList(),
    'wasNeverOpened': wasNeverOpened,
    'isHighEngagement': isHighEngagement,
    'tags': tags,
    'socialNetwork': socialNetwork,
  };

  factory ContentInteraction.fromJson(Map<String, dynamic> json) => ContentInteraction(
    postId: json['postId'],
    postTitle: json['postTitle'],
    postUrl: json['postUrl'],
    folderPath: json['folderPath'],
    savedDate: DateTime.parse(json['savedDate']),
    firstOpened: json['firstOpened'] != null ? DateTime.parse(json['firstOpened']) : null,
    lastOpened: json['lastOpened'] != null ? DateTime.parse(json['lastOpened']) : null,
    openCount: json['openCount'] ?? 0,
    openTimes: (json['openTimes'] as List?)?.map((t) => DateTime.parse(t)).toList() ?? [],
    viewDurations: (json['viewDurations'] as List?)?.map((d) => Duration(milliseconds: d)).toList() ?? [],
    wasNeverOpened: json['wasNeverOpened'] ?? true,
    isHighEngagement: json['isHighEngagement'] ?? false,
    tags: List<String>.from(json['tags'] ?? []),
    socialNetwork: json['socialNetwork'],
  );
}

// Metriche organizzative struttura cartelle
class OrganizationalMetrics {
  final double avgFolderDepth;
  final int maxFolderDepth;
  final int totalFolders;
  final int flatFolders; // Cartelle senza sottocartelle
  final int nestedFolders; // Cartelle con sottocartelle
  final int emptyFolders; // Cartelle senza contenuti
  final double foldersUtilizationRate; // % cartelle con contenuti
  final Map<int, int> depthDistribution; // depth -> count
  final List<String> underutilizedFolders; // Cartelle poco usate
  final List<String> overutilizedFolders; // Cartelle troppo piene
  final double organizationalEfficiency; // Score efficienza 0-1

  OrganizationalMetrics({
    required this.avgFolderDepth,
    required this.maxFolderDepth,
    required this.totalFolders,
    required this.flatFolders,
    required this.nestedFolders,
    required this.emptyFolders,
    required this.foldersUtilizationRate,
    required this.depthDistribution,
    required this.underutilizedFolders,
    required this.overutilizedFolders,
    required this.organizationalEfficiency,
  });

  Map<String, dynamic> toJson() => {
    'avgFolderDepth': avgFolderDepth,
    'maxFolderDepth': maxFolderDepth,
    'totalFolders': totalFolders,
    'flatFolders': flatFolders,
    'nestedFolders': nestedFolders,
    'emptyFolders': emptyFolders,
    'foldersUtilizationRate': foldersUtilizationRate,
    'depthDistribution': depthDistribution.map((k, v) => MapEntry(k.toString(), v)),
    'underutilizedFolders': underutilizedFolders,
    'overutilizedFolders': overutilizedFolders,
    'organizationalEfficiency': organizationalEfficiency,
  };

  factory OrganizationalMetrics.fromJson(Map<String, dynamic> json) => OrganizationalMetrics(
    avgFolderDepth: json['avgFolderDepth'].toDouble(),
    maxFolderDepth: json['maxFolderDepth'],
    totalFolders: json['totalFolders'],
    flatFolders: json['flatFolders'],
    nestedFolders: json['nestedFolders'],
    emptyFolders: json['emptyFolders'],
    foldersUtilizationRate: json['foldersUtilizationRate'].toDouble(),
    depthDistribution: Map<int, int>.from(
      json['depthDistribution'].map((k, v) => MapEntry(int.parse(k), v))
    ),
    underutilizedFolders: List<String>.from(json['underutilizedFolders']),
    overutilizedFolders: List<String>.from(json['overutilizedFolders']),
    organizationalEfficiency: json['organizationalEfficiency'].toDouble(),
  );
}

// Statistiche comportamentali avanzate
class BehavioralStats {
  final Duration avgSessionTime;
  final double revisitationRate; // % contenuti riaperti
  final double abandonmentRate; // % contenuti mai aperti
  final Duration avgSaveToOpenTime; // Tempo medio salvataggio->apertura
  final Duration avgActionInterval; // Tempo medio tra azioni
  final Map<String, double> actionEfficiency; // action -> efficiency score
  final List<String> usagePatterns; // Pattern rilevati
  final double consistencyScore; // Consistenza nell'uso (0-1)
  final Map<String, int> preferredActions; // Azioni preferite
  final int batchActionsDetected; // Numero sessioni con azioni batch

  BehavioralStats({
    required this.avgSessionTime,
    required this.revisitationRate,
    required this.abandonmentRate,
    required this.avgSaveToOpenTime,
    required this.avgActionInterval,
    required this.actionEfficiency,
    required this.usagePatterns,
    required this.consistencyScore,
    required this.preferredActions,
    required this.batchActionsDetected,
  });

  Map<String, dynamic> toJson() => {
    'avgSessionTime': avgSessionTime.inMilliseconds,
    'revisitationRate': revisitationRate,
    'abandonmentRate': abandonmentRate,
    'avgSaveToOpenTime': avgSaveToOpenTime.inMilliseconds,
    'avgActionInterval': avgActionInterval.inMilliseconds,
    'actionEfficiency': actionEfficiency,
    'usagePatterns': usagePatterns,
    'consistencyScore': consistencyScore,
    'preferredActions': preferredActions,
    'batchActionsDetected': batchActionsDetected,
  };

  factory BehavioralStats.fromJson(Map<String, dynamic> json) => BehavioralStats(
    avgSessionTime: Duration(milliseconds: json['avgSessionTime']),
    revisitationRate: json['revisitationRate'].toDouble(),
    abandonmentRate: json['abandonmentRate'].toDouble(),
    avgSaveToOpenTime: Duration(milliseconds: json['avgSaveToOpenTime']),
    avgActionInterval: Duration(milliseconds: json['avgActionInterval']),
    actionEfficiency: Map<String, double>.from(json['actionEfficiency']),
    usagePatterns: List<String>.from(json['usagePatterns']),
    consistencyScore: json['consistencyScore'].toDouble(),
    preferredActions: Map<String, int>.from(json['preferredActions']),
    batchActionsDetected: json['batchActionsDetected'],
  );
}

// Micro-timing e pattern temporali precisi
class MicroTimingStats {
  final Map<String, int> hourlyPreciseUsage; // "14:30-14:45" -> count
  final Map<String, double> peakUsageWindows; // Finestre di picco con score
  final Map<String, int> weekdayVsWeekend; // "weekday"/"weekend" -> usage
  final Map<String, int> monthlyPatterns; // "2024-01" -> usage
  final Map<String, int> seasonalTrends; // "winter"/"spring"/etc -> usage
  final List<String> detectedSchedules; // Pattern orari rilevati
  final Duration avgTimeToFirstAction; // Tempo app-aperta -> prima azione
  final Map<String, Duration> actionSequenceTiming; // Sequenze azioni comuni
  final double temporalConsistency; // Consistenza orari utilizzo (0-1)

  MicroTimingStats({
    required this.hourlyPreciseUsage,
    required this.peakUsageWindows,
    required this.weekdayVsWeekend,
    required this.monthlyPatterns,
    required this.seasonalTrends,
    required this.detectedSchedules,
    required this.avgTimeToFirstAction,
    required this.actionSequenceTiming,
    required this.temporalConsistency,
  });

  Map<String, dynamic> toJson() => {
    'hourlyPreciseUsage': hourlyPreciseUsage,
    'peakUsageWindows': peakUsageWindows,
    'weekdayVsWeekend': weekdayVsWeekend,
    'monthlyPatterns': monthlyPatterns,
    'seasonalTrends': seasonalTrends,
    'detectedSchedules': detectedSchedules,
    'avgTimeToFirstAction': avgTimeToFirstAction.inMilliseconds,
    'actionSequenceTiming': actionSequenceTiming.map((k, v) => MapEntry(k, v.inMilliseconds)),
    'temporalConsistency': temporalConsistency,
  };

  factory MicroTimingStats.fromJson(Map<String, dynamic> json) => MicroTimingStats(
    hourlyPreciseUsage: Map<String, int>.from(json['hourlyPreciseUsage']),
    peakUsageWindows: Map<String, double>.from(json['peakUsageWindows']),
    weekdayVsWeekend: Map<String, int>.from(json['weekdayVsWeekend']),
    monthlyPatterns: Map<String, int>.from(json['monthlyPatterns']),
    seasonalTrends: Map<String, int>.from(json['seasonalTrends']),
    detectedSchedules: List<String>.from(json['detectedSchedules']),
    avgTimeToFirstAction: Duration(milliseconds: json['avgTimeToFirstAction']),
    actionSequenceTiming: Map<String, Duration>.from(
      json['actionSequenceTiming'].map((k, v) => MapEntry(k, Duration(milliseconds: v)))
    ),
    temporalConsistency: json['temporalConsistency'].toDouble(),
  );
}

// Analisi qualità contenuti
class ContentQualityMetrics {
  final int totalContent;
  final int duplicateContent; // Contenuti duplicati o simili
  final int neverOpenedContent; // Contenuti mai aperti
  final int highEngagementContent; // Contenuti molto visitati
  final double contentEfficiencyScore; // Rapporto contenuti utili/totali
  final Map<String, int> socialNetworkDistribution; // Distribuzione sorgenti
  final Map<String, double> socialNetworkEngagement; // Engagement per sorgente
  final List<String> recommendedCleanup; // Contenuti da rimuovere
  final double contentRetentionRate; // % contenuti conservati a lungo termine

  ContentQualityMetrics({
    required this.totalContent,
    required this.duplicateContent,
    required this.neverOpenedContent,
    required this.highEngagementContent,
    required this.contentEfficiencyScore,
    required this.socialNetworkDistribution,
    required this.socialNetworkEngagement,
    required this.recommendedCleanup,
    required this.contentRetentionRate,
  });

  Map<String, dynamic> toJson() => {
    'totalContent': totalContent,
    'duplicateContent': duplicateContent,
    'neverOpenedContent': neverOpenedContent,
    'highEngagementContent': highEngagementContent,
    'contentEfficiencyScore': contentEfficiencyScore,
    'socialNetworkDistribution': socialNetworkDistribution,
    'socialNetworkEngagement': socialNetworkEngagement,
    'recommendedCleanup': recommendedCleanup,
    'contentRetentionRate': contentRetentionRate,
  };

  factory ContentQualityMetrics.fromJson(Map<String, dynamic> json) => ContentQualityMetrics(
    totalContent: json['totalContent'],
    duplicateContent: json['duplicateContent'],
    neverOpenedContent: json['neverOpenedContent'],
    highEngagementContent: json['highEngagementContent'],
    contentEfficiencyScore: json['contentEfficiencyScore'].toDouble(),
    socialNetworkDistribution: Map<String, int>.from(json['socialNetworkDistribution']),
    socialNetworkEngagement: Map<String, double>.from(json['socialNetworkEngagement']),
    recommendedCleanup: List<String>.from(json['recommendedCleanup']),
    contentRetentionRate: json['contentRetentionRate'].toDouble(),
  );
}

// Insight automatici basati sui dati
class AnalyticsInsight {
  final String id;
  final String type; // 'productivity', 'organization', 'behavior', 'content'
  final String title;
  final String description;
  final String recommendation;
  final double confidence; // Confidenza nell'insight (0-1)
  final Map<String, dynamic> supportingData; // Dati che supportano l'insight
  final DateTime generatedAt;
  final bool isActionable; // Se l'utente può agire su questo insight

  AnalyticsInsight({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.recommendation,
    required this.confidence,
    required this.supportingData,
    required this.generatedAt,
    required this.isActionable,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'description': description,
    'recommendation': recommendation,
    'confidence': confidence,
    'supportingData': supportingData,
    'generatedAt': generatedAt.toIso8601String(),
    'isActionable': isActionable,
  };

  factory AnalyticsInsight.fromJson(Map<String, dynamic> json) => AnalyticsInsight(
    id: json['id'],
    type: json['type'],
    title: json['title'],
    description: json['description'],
    recommendation: json['recommendation'],
    confidence: json['confidence'].toDouble(),
    supportingData: Map<String, dynamic>.from(json['supportingData']),
    generatedAt: DateTime.parse(json['generatedAt']),
    isActionable: json['isActionable'],
  );
}

// Aggregato di tutte le statistiche avanzate
class AdvancedAnalyticsData {
  final List<SessionData> sessions;
  final List<ContentInteraction> contentInteractions;
  final OrganizationalMetrics organizationalMetrics;
  final BehavioralStats behavioralStats;
  final MicroTimingStats microTimingStats;
  final ContentQualityMetrics contentQualityMetrics;
  final List<AnalyticsInsight> insights;
  final DateTime lastCalculated;

  AdvancedAnalyticsData({
    required this.sessions,
    required this.contentInteractions,
    required this.organizationalMetrics,
    required this.behavioralStats,
    required this.microTimingStats,
    required this.contentQualityMetrics,
    required this.insights,
    required this.lastCalculated,
  });

  Map<String, dynamic> toJson() => {
    'sessions': sessions.map((s) => s.toJson()).toList(),
    'contentInteractions': contentInteractions.map((c) => c.toJson()).toList(),
    'organizationalMetrics': organizationalMetrics.toJson(),
    'behavioralStats': behavioralStats.toJson(),
    'microTimingStats': microTimingStats.toJson(),
    'contentQualityMetrics': contentQualityMetrics.toJson(),
    'insights': insights.map((i) => i.toJson()).toList(),
    'lastCalculated': lastCalculated.toIso8601String(),
  };

  factory AdvancedAnalyticsData.fromJson(Map<String, dynamic> json) => AdvancedAnalyticsData(
    sessions: (json['sessions'] as List).map((s) => SessionData.fromJson(s)).toList(),
    contentInteractions: (json['contentInteractions'] as List).map((c) => ContentInteraction.fromJson(c)).toList(),
    organizationalMetrics: OrganizationalMetrics.fromJson(json['organizationalMetrics']),
    behavioralStats: BehavioralStats.fromJson(json['behavioralStats']),
    microTimingStats: MicroTimingStats.fromJson(json['microTimingStats']),
    contentQualityMetrics: ContentQualityMetrics.fromJson(json['contentQualityMetrics']),
    insights: (json['insights'] as List).map((i) => AnalyticsInsight.fromJson(i)).toList(),
    lastCalculated: DateTime.parse(json['lastCalculated']),
  );
}