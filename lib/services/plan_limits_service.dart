import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';

class PlanFeatureRule {
  final bool enabled;
  final int limit;
  final String period;
  final bool requiresAd;

  PlanFeatureRule({
    required this.enabled,
    required this.limit,
    required this.period,
    required this.requiresAd,
  });

  factory PlanFeatureRule.fromMap(Map<String, dynamic> map) {
    return PlanFeatureRule(
      enabled: map['enabled'] ?? false,
      limit: map['limit'] ?? 0,
      period: map['period'] ?? 'total',
      requiresAd: map['requiresAd'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'limit': limit,
      'period': period,
      'requiresAd': requiresAd,
    };
  }
}

class PlanFeatureUsage {
  final String feature;
  final int count;
  final int limit;
  final String period;
  final bool enabled;
  final bool requiresAd;
  final String tier;

  PlanFeatureUsage({
    required this.feature,
    required this.count,
    required this.limit,
    required this.period,
    required this.enabled,
    required this.requiresAd,
    required this.tier,
  });

  int get remaining => limit <= 0 ? -1 : (limit - count).clamp(0, limit);
  bool get isUnlimited => limit <= 0;
  bool get isReached => !isUnlimited && count >= limit;

  factory PlanFeatureUsage.fromMap(
      String feature, Map<String, dynamic>? map, String tier) {
    if (map == null) {
      return PlanFeatureUsage(
        feature: feature,
        count: 0,
        limit: 0,
        period: 'total',
        enabled: false,
        requiresAd: false,
        tier: tier,
      );
    }
    return PlanFeatureUsage(
      feature: feature,
      count: map['count'] ?? 0,
      limit: map['limit'] ?? 0,
      period: map['period'] ?? 'total',
      enabled: map['enabled'] ?? true,
      requiresAd: map['requiresAd'] ?? false,
      tier: tier,
    );
  }
}

class PlanLimitsService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final AuthService _auth = AuthService();

  static Map<String, dynamic>? _cachedRules;
  static DateTime? _lastRulesFetch;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _rulesSubscription;

  static Map<String, dynamic>? get cachedRules => _cachedRules;

  static Map<String, PlanFeatureUsage>? _cachedUsage;
  static DateTime? _lastUsageFetch;
  static String? _cachedUsageUserId;
  static String? _cachedUsageTier;

  static final Map<String, dynamic> defaultRules = {
    'root_folders': {
      'free': {
        'enabled': true,
        'limit': 10,
        'period': 'total',
        'requiresAd': false
      },
      'premium': {
        'enabled': true,
        'limit': 0,
        'period': 'total',
        'requiresAd': false
      },
    },
    'child_folders': {
      'free': {
        'enabled': true,
        'limit': 4,
        'period': 'total',
        'requiresAd': false
      },
      'premium': {
        'enabled': true,
        'limit': 0,
        'period': 'total',
        'requiresAd': false
      },
    },
    'folder_levels': {
      'free': {
        'enabled': true,
        'limit': 1,
        'period': 'total',
        'requiresAd': false
      },
      'premium': {
        'enabled': true,
        'limit': 5,
        'period': 'total',
        'requiresAd': false
      },
    },
    'manual_tags': {
      'free': {
        'enabled': false,
        'limit': 0,
        'period': 'total',
        'requiresAd': false
      },
      'premium': {
        'enabled': true,
        'limit': 0,
        'period': 'total',
        'requiresAd': false
      },
    },
    'share_folder': {
      'free': {
        'enabled': true,
        'limit': 1,
        'period': 'day',
        'requiresAd': true
      },
      'premium': {
        'enabled': true,
        'limit': 0,
        'period': 'day',
        'requiresAd': false
      },
    },
    'share_post': {
      'free': {
        'enabled': true,
        'limit': 3,
        'period': 'day',
        'requiresAd': true
      },
      'premium': {
        'enabled': true,
        'limit': 0,
        'period': 'day',
        'requiresAd': false
      },
    },
    'import_shared': {
      'free': {
        'enabled': true,
        'limit': 5,
        'period': 'day',
        'requiresAd': true
      },
      'premium': {
        'enabled': true,
        'limit': 0,
        'period': 'day',
        'requiresAd': false
      },
    },
    'reminders': {
      'free': {
        'enabled': true,
        'limit': 0,
        'period': 'total',
        'requiresAd': true
      },
      'premium': {
        'enabled': true,
        'limit': 0,
        'period': 'total',
        'requiresAd': false
      },
    },
  };

  static void startLiveSync() {
    _rulesSubscription ??=
        _db.doc('config/plan_limits').snapshots().listen((snapshot) {
      _cachedRules = _mergeWithDefaultRules(
        snapshot.data()?['featureRules'] as Map<String, dynamic>? ?? {},
      );
      _lastRulesFetch = DateTime.now();
      _cachedUsage = null;
      _lastUsageFetch = null;
    }, onError: (e) {
      debugPrint('Error listening plan limits: $e');
    });
  }

  static Future<void> stopLiveSync() async {
    await _rulesSubscription?.cancel();
    _rulesSubscription = null;
  }

  static void clearCache() {
    _cachedRules = null;
    _lastRulesFetch = null;
    invalidateUsageCache();
  }

  static void invalidateUsageCache() {
    _cachedUsage = null;
    _lastUsageFetch = null;
    _cachedUsageUserId = null;
    _cachedUsageTier = null;
  }

  static Future<String> _currentTier({bool forceRefresh = false}) async {
    if (forceRefresh) {
      await _auth.reloadCurrentUserFromFirestore();
    }
    final role = _auth.currentUser?.effectiveRole ?? AppUserRole.free;
    return role == AppUserRole.free ? 'free' : 'premium';
  }

  static Map<String, dynamic> _copyMap(Map<dynamic, dynamic> source) {
    return source.map((key, value) {
      if (value is Map) {
        return MapEntry(key.toString(), _copyMap(value));
      }
      if (value is List) {
        return MapEntry(key.toString(), List<dynamic>.from(value));
      }
      return MapEntry(key.toString(), value);
    });
  }

  static Map<String, dynamic> _mergeWithDefaultRules(
    Map<String, dynamic> source,
  ) {
    final rules = _copyMap(source);
    defaultRules.forEach((key, value) {
      final defaultsForFeature = _copyMap(Map<dynamic, dynamic>.from(value));
      if (rules[key] is! Map) {
        rules[key] = defaultsForFeature;
        return;
      }

      final feature = _copyMap(Map<dynamic, dynamic>.from(rules[key] as Map));
      for (final tier in const ['free', 'premium']) {
        if (feature[tier] is! Map) {
          feature[tier] = _copyMap(
            Map<dynamic, dynamic>.from(defaultsForFeature[tier] as Map),
          );
          continue;
        }

        final tierRules =
            _copyMap(Map<dynamic, dynamic>.from(feature[tier] as Map));
        final defaultTierRules =
            Map<dynamic, dynamic>.from(defaultsForFeature[tier] as Map);
        defaultTierRules.forEach((field, defaultValue) {
          tierRules.putIfAbsent(field.toString(), () => defaultValue);
        });
        feature[tier] = tierRules;
      }
      rules[key] = feature;
    });
    return rules;
  }

  static Future<Map<String, dynamic>> getFeatureRules({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedRules != null &&
        _lastRulesFetch != null &&
        DateTime.now().difference(_lastRulesFetch!) <
            const Duration(minutes: 5)) {
      return _cachedRules!;
    }

    try {
      final doc = await _db.doc('config/plan_limits').get();
      final rules = _mergeWithDefaultRules(
        doc.data()?['featureRules'] as Map<String, dynamic>? ?? {},
      );

      _cachedRules = rules;
      _lastRulesFetch = DateTime.now();
      return rules;
    } catch (e) {
      debugPrint('Error fetching plan limits: $e');
    }
    return {};
  }

  static Future<PlanFeatureRule> getRule(
    String feature, {
    bool forceRefresh = false,
  }) async {
    final rules = await getFeatureRules(forceRefresh: forceRefresh);
    final tier = await _currentTier(forceRefresh: forceRefresh);

    final featureData = rules[feature] as Map<String, dynamic>?;
    if (featureData != null && featureData[tier] != null) {
      return PlanFeatureRule.fromMap(
          Map<String, dynamic>.from(featureData[tier]));
    }

    // Default fallback
    return PlanFeatureRule(
        enabled: true, limit: 0, period: 'total', requiresAd: false);
  }

  static Future<Map<String, PlanFeatureUsage>> getUsage({
    bool forceRefresh = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return {};

    final tier = await _currentTier(forceRefresh: forceRefresh);

    if (!forceRefresh &&
        _cachedUsage != null &&
        _lastUsageFetch != null &&
        _cachedUsageUserId == user.id &&
        _cachedUsageTier == tier &&
        DateTime.now().difference(_lastUsageFetch!) <
            const Duration(seconds: 30)) {
      return _cachedUsage!;
    }

    try {
      // In SaveIn, we might need a different way to track usage if not using a dedicated endpoint
      // For now, let's assume we'll implement a similar logic to SmartChef or just read from a collection
      final rules = await getFeatureRules(forceRefresh: forceRefresh);
      final usageDoc = await _db.collection('feature_usage').doc(user.id).get();
      final usageData = usageDoc.data() ?? {};

      final Map<String, PlanFeatureUsage> result = {};
      rules.forEach((key, value) {
        final featureRules = value as Map<String, dynamic>;
        final rule = featureRules[tier] as Map<String, dynamic>;

        // Calculate count based on period
        final period = rule['period'] ?? 'total';
        int count = 0;
        if (usageData[key] != null) {
          final featUsage = usageData[key] as Map<String, dynamic>;
          final periodKey = _getPeriodKey(period);
          count = featUsage[periodKey] ?? 0;
        }

        result[key] = PlanFeatureUsage(
          feature: key,
          count: count,
          limit: rule['limit'] ?? 0,
          period: period,
          enabled: rule['enabled'] ?? true,
          requiresAd: rule['requiresAd'] ?? false,
          tier: tier,
        );
      });

      _cachedUsage = result;
      _lastUsageFetch = DateTime.now();
      _cachedUsageUserId = user.id;
      _cachedUsageTier = tier;
      return result;
    } catch (e) {
      debugPrint('Error fetching usage: $e');
      return {};
    }
  }

  static String _getPeriodKey(String period) {
    final now = DateTime.now();
    switch (period) {
      case 'day':
        return 'd_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      case 'week':
        // Simple week calculation
        final week = (now.day / 7).ceil();
        return 'w_${now.year}${now.month.toString().padLeft(2, '0')}_$week';
      case 'month':
        return 'm_${now.year}${now.month.toString().padLeft(2, '0')}';
      default:
        return 'total';
    }
  }

  static Future<bool> canUseFeature(String feature) async {
    final usage = await getUsage(forceRefresh: true);
    final featUsage = usage[feature];
    if (featUsage == null) return true;
    if (!featUsage.enabled) return false;
    if (featUsage.isUnlimited) return true;
    return !featUsage.isReached;
  }

  static Future<void> consumeOrThrow(
    String feature, {
    required String featureName,
  }) async {
    final usage = await getUsage(forceRefresh: true);
    final featUsage = usage[feature];
    if (featUsage == null) return;
    if (!featUsage.enabled) {
      throw Exception(
          'La funzione $featureName è temporaneamente disabilitata.');
    }
    if (!featUsage.isUnlimited && featUsage.isReached) {
      throw Exception('Hai raggiunto il limite per $featureName.');
    }
  }

  static Future<void> recordFeatureSuccess(String feature) async {
    await incrementUsage(feature);
  }

  static Future<void> incrementUsage(String feature) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final rules = await getFeatureRules(forceRefresh: true);
    final featureData = rules[feature] as Map<String, dynamic>?;
    if (featureData == null) return;

    final tier = await _currentTier(forceRefresh: true);
    final rule = featureData[tier] as Map<String, dynamic>;
    final period = rule['period'] ?? 'total';
    final periodKey = _getPeriodKey(period);

    final ref = _db.collection('feature_usage').doc(user.id);

    await _db.runTransaction((transaction) async {
      final doc = await transaction.get(ref);
      if (!doc.exists) {
        transaction.set(ref, {
          feature: {
            periodKey: 1,
            'last_update': FieldValue.serverTimestamp(),
          }
        });
      } else {
        final data = doc.data()!;
        final featData = Map<String, dynamic>.from(data[feature] ?? {});
        final currentCount = featData[periodKey] ?? 0;
        featData[periodKey] = currentCount + 1;
        featData['last_update'] = FieldValue.serverTimestamp();
        transaction.update(ref, {feature: featData});
      }
    });

    // Invalidate cache
    _cachedUsage = null;
    _lastUsageFetch = null;
    _cachedUsageUserId = null;
    _cachedUsageTier = null;
  }
}
