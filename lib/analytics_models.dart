// analytics_models.dart

import 'package:flutter/foundation.dart';

// Tipi di eventi che tracciamo
enum AnalyticsEventType {
  appOpened,
  appClosed,
  postViewed,
  postCreated,
  postDeleted,
  folderCreated,
  folderDeleted,
  folderOpened,
  searchPerformed,
  tagUsed,
  postShared,
  themeChanged,
}

// Informazioni del dispositivo
class DeviceInfo {
  final String deviceType; // 'iPhone 15', 'Samsung Galaxy S24', etc.
  final String platform; // 'iOS', 'Android', 'Web'
  final String osVersion;
  final String appVersion;
  final DateTime firstInstall;

  DeviceInfo({
    required this.deviceType,
    required this.platform,
    required this.osVersion,
    required this.appVersion,
    required this.firstInstall,
  });

  Map<String, dynamic> toJson() => {
    'deviceType': deviceType,
    'platform': platform,
    'osVersion': osVersion,
    'appVersion': appVersion,
    'firstInstall': firstInstall.toIso8601String(),
  };

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
    deviceType: json['deviceType'],
    platform: json['platform'],
    osVersion: json['osVersion'],
    appVersion: json['appVersion'],
    firstInstall: DateTime.parse(json['firstInstall']),
  );
}

// Evento di analytics
class AnalyticsEvent {
  final String id;
  final AnalyticsEventType type;
  final DateTime timestamp;
  final Map<String, dynamic> properties;

  AnalyticsEvent({
    required this.id,
    required this.type,
    required this.timestamp,
    this.properties = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'timestamp': timestamp.toIso8601String(),
    'properties': properties,
  };

  factory AnalyticsEvent.fromJson(Map<String, dynamic> json) => AnalyticsEvent(
    id: json['id'],
    type: AnalyticsEventType.values.firstWhere((e) => e.name == json['type']),
    timestamp: DateTime.parse(json['timestamp']),
    properties: Map<String, dynamic>.from(json['properties']),
  );
}

// Statistiche di utilizzo giornaliero
class DailyUsageStats {
  final DateTime date;
  final int appOpenCount;
  final int postsViewed;
  final int postsCreated;
  final int foldersCreated;
  final int searchesPerformed;
  final Duration totalTimeSpent;
  final Map<String, int> socialNetworkUsage; // domain -> count
  final Map<String, int> folderUsage; // folderName -> count
  final Map<String, int> tagUsage; // tag -> count

  DailyUsageStats({
    required this.date,
    required this.appOpenCount,
    required this.postsViewed,
    required this.postsCreated,
    required this.foldersCreated,
    required this.searchesPerformed,
    required this.totalTimeSpent,
    required this.socialNetworkUsage,
    required this.folderUsage,
    required this.tagUsage,
  });

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'appOpenCount': appOpenCount,
    'postsViewed': postsViewed,
    'postsCreated': postsCreated,
    'foldersCreated': foldersCreated,
    'searchesPerformed': searchesPerformed,
    'totalTimeSpent': totalTimeSpent.inMilliseconds,
    'socialNetworkUsage': socialNetworkUsage,
    'folderUsage': folderUsage,
    'tagUsage': tagUsage,
  };

  factory DailyUsageStats.fromJson(Map<String, dynamic> json) => DailyUsageStats(
    date: DateTime.parse(json['date']),
    appOpenCount: json['appOpenCount'],
    postsViewed: json['postsViewed'],
    postsCreated: json['postsCreated'],
    foldersCreated: json['foldersCreated'],
    searchesPerformed: json['searchesPerformed'],
    totalTimeSpent: Duration(milliseconds: json['totalTimeSpent']),
    socialNetworkUsage: Map<String, int>.from(json['socialNetworkUsage']),
    folderUsage: Map<String, int>.from(json['folderUsage']),
    tagUsage: Map<String, int>.from(json['tagUsage']),
  );
}

// Statistiche orarie (0-23)
class HourlyUsageStats {
  final Map<int, int> hourlyActivity; // hour -> event count
  final Map<int, Duration> hourlyTimeSpent; // hour -> duration

  HourlyUsageStats({
    required this.hourlyActivity,
    required this.hourlyTimeSpent,
  });

  Map<String, dynamic> toJson() => {
    'hourlyActivity': hourlyActivity.map((k, v) => MapEntry(k.toString(), v)),
    'hourlyTimeSpent': hourlyTimeSpent.map((k, v) => MapEntry(k.toString(), v.inMilliseconds)),
  };

  factory HourlyUsageStats.fromJson(Map<String, dynamic> json) => HourlyUsageStats(
    hourlyActivity: Map<int, int>.from(
      json['hourlyActivity'].map((k, v) => MapEntry(int.parse(k), v))
    ),
    hourlyTimeSpent: Map<int, Duration>.from(
      json['hourlyTimeSpent'].map((k, v) => MapEntry(int.parse(k), Duration(milliseconds: v)))
    ),
  );
}

// Statistiche settimanali (0=lunedì, 6=domenica)
class WeeklyUsageStats {
  final Map<int, int> weekdayActivity; // weekday -> event count
  final Map<int, Duration> weekdayTimeSpent; // weekday -> duration

  WeeklyUsageStats({
    required this.weekdayActivity,
    required this.weekdayTimeSpent,
  });

  Map<String, dynamic> toJson() => {
    'weekdayActivity': weekdayActivity.map((k, v) => MapEntry(k.toString(), v)),
    'weekdayTimeSpent': weekdayTimeSpent.map((k, v) => MapEntry(k.toString(), v.inMilliseconds)),
  };

  factory WeeklyUsageStats.fromJson(Map<String, dynamic> json) => WeeklyUsageStats(
    weekdayActivity: Map<int, int>.from(
      json['weekdayActivity'].map((k, v) => MapEntry(int.parse(k), v))
    ),
    weekdayTimeSpent: Map<int, Duration>.from(
      json['weekdayTimeSpent'].map((k, v) => MapEntry(int.parse(k), Duration(milliseconds: v)))
    ),
  );
}

// Post con statistiche di visualizzazione
class PostViewStats {
  final String postId;
  final String postTitle;
  final String folderName;
  final int viewCount;
  final DateTime lastViewed;
  final DateTime firstViewed;
  final List<DateTime> viewTimes; // Per vedere i pattern temporali

  PostViewStats({
    required this.postId,
    required this.postTitle,
    required this.folderName,
    required this.viewCount,
    required this.lastViewed,
    required this.firstViewed,
    required this.viewTimes,
  });

  Map<String, dynamic> toJson() => {
    'postId': postId,
    'postTitle': postTitle,
    'folderName': folderName,
    'viewCount': viewCount,
    'lastViewed': lastViewed.toIso8601String(),
    'firstViewed': firstViewed.toIso8601String(),
    'viewTimes': viewTimes.map((t) => t.toIso8601String()).toList(),
  };

  factory PostViewStats.fromJson(Map<String, dynamic> json) => PostViewStats(
    postId: json['postId'],
    postTitle: json['postTitle'],
    folderName: json['folderName'],
    viewCount: json['viewCount'],
    lastViewed: DateTime.parse(json['lastViewed']),
    firstViewed: DateTime.parse(json['firstViewed']),
    viewTimes: (json['viewTimes'] as List).map((t) => DateTime.parse(t)).toList(),
  );
}

// Statistiche aggregate complessive
class OverallStats {
  final int totalPosts;
  final int totalFolders;
  final int totalAppOpens;
  final Duration totalTimeInApp;
  final DateTime firstUse;
  final DateTime lastUse;
  final int streakDays; // Giorni consecutivi di utilizzo
  final Map<String, int> topSocialNetworks; // domain -> count
  final Map<String, int> topFolders; // folderName -> usage count
  final Map<String, int> topTags; // tag -> usage count
  final List<String> mostViewedPosts; // postIds ordinati per view count

  OverallStats({
    required this.totalPosts,
    required this.totalFolders,
    required this.totalAppOpens,
    required this.totalTimeInApp,
    required this.firstUse,
    required this.lastUse,
    required this.streakDays,
    required this.topSocialNetworks,
    required this.topFolders,
    required this.topTags,
    required this.mostViewedPosts,
  });

  Map<String, dynamic> toJson() => {
    'totalPosts': totalPosts,
    'totalFolders': totalFolders,
    'totalAppOpens': totalAppOpens,
    'totalTimeInApp': totalTimeInApp.inMilliseconds,
    'firstUse': firstUse.toIso8601String(),
    'lastUse': lastUse.toIso8601String(),
    'streakDays': streakDays,
    'topSocialNetworks': topSocialNetworks,
    'topFolders': topFolders,
    'topTags': topTags,
    'mostViewedPosts': mostViewedPosts,
  };

  factory OverallStats.fromJson(Map<String, dynamic> json) => OverallStats(
    totalPosts: json['totalPosts'],
    totalFolders: json['totalFolders'],
    totalAppOpens: json['totalAppOpens'],
    totalTimeInApp: Duration(milliseconds: json['totalTimeInApp']),
    firstUse: DateTime.parse(json['firstUse']),
    lastUse: DateTime.parse(json['lastUse']),
    streakDays: json['streakDays'],
    topSocialNetworks: Map<String, int>.from(json['topSocialNetworks']),
    topFolders: Map<String, int>.from(json['topFolders']),
    topTags: Map<String, int>.from(json['topTags']),
    mostViewedPosts: List<String>.from(json['mostViewedPosts']),
  );
}

// Classe per raggruppare tutte le statistiche
class AnalyticsData {
  final DeviceInfo deviceInfo;
  final OverallStats overallStats;
  final List<DailyUsageStats> dailyStats;
  final HourlyUsageStats hourlyStats;
  final WeeklyUsageStats weeklyStats;
  final List<PostViewStats> postViewStats;

  AnalyticsData({
    required this.deviceInfo,
    required this.overallStats,
    required this.dailyStats,
    required this.hourlyStats,
    required this.weeklyStats,
    required this.postViewStats,
  });

  Map<String, dynamic> toJson() => {
    'deviceInfo': deviceInfo.toJson(),
    'overallStats': overallStats.toJson(),
    'dailyStats': dailyStats.map((s) => s.toJson()).toList(),
    'hourlyStats': hourlyStats.toJson(),
    'weeklyStats': weeklyStats.toJson(),
    'postViewStats': postViewStats.map((s) => s.toJson()).toList(),
  };

  factory AnalyticsData.fromJson(Map<String, dynamic> json) => AnalyticsData(
    deviceInfo: DeviceInfo.fromJson(json['deviceInfo']),
    overallStats: OverallStats.fromJson(json['overallStats']),
    dailyStats: (json['dailyStats'] as List).map((s) => DailyUsageStats.fromJson(s)).toList(),
    hourlyStats: HourlyUsageStats.fromJson(json['hourlyStats']),
    weeklyStats: WeeklyUsageStats.fromJson(json['weeklyStats']),
    postViewStats: (json['postViewStats'] as List).map((s) => PostViewStats.fromJson(s)).toList(),
  );
}