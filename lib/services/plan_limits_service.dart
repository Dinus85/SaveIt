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

  /// Incrementato a ogni aggiornamento live di `config/plan_limits`.
  /// L'UI può ascoltarlo per riflettere subito `requiresAd` / limiti.
  static final ValueNotifier<int> rulesRevision = ValueNotifier<int>(0);

  static Map<String, dynamic>? get cachedRules => _cachedRules;

  /// Catalogo voci allineato alla pagina Limiti della dashboard.
  static const List<({String id, String name})> dashboardFeatureCatalog = [
    (id: 'root_folders', name: 'Cartelle nella Home'),
    (
      id: 'child_folders',
      name: 'Numero di sottocartelle per ogni cartella',
    ),
    (
      id: 'folder_levels',
      name: 'Livelli di profondità per sottocartelle - Home-L1-L2-L3-ETC',
    ),
    (id: 'manual_tags', name: 'Tag manuali'),
    (id: 'share_folder', name: 'Condivisione Cartella'),
    (id: 'share_post', name: 'Condivisione Post'),
    (id: 'import_shared_post', name: 'Importazione post'),
    (id: 'import_shared_folder', name: 'Importazione cartelle'),
    (
      id: 'home_banner_every_n_folders',
      name: 'Banner pubblicitari ogni N cartelle (Home e sottocartelle)',
    ),
    (
      id: 'post_banner_every_n_posts',
      name: 'Banner pubblicitari ogni N post',
    ),
    (id: 'reminders', name: 'Reminder'),
  ];

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
    'import_shared_post': {
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
    'import_shared_folder': {
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
    'home_banner_every_n_folders': {
      'free': {
        'enabled': true,
        'limit': 3,
        'period': 'total',
        'requiresAd': false
      },
      'premium': {
        'enabled': false,
        'limit': 0,
        'period': 'total',
        'requiresAd': false
      },
    },
    'subfolder_banner_every_n_folders': {
      'free': {
        'enabled': true,
        'limit': 3,
        'period': 'total',
        'requiresAd': false
      },
      'premium': {
        'enabled': false,
        'limit': 0,
        'period': 'total',
        'requiresAd': false
      },
    },
    'post_banner_every_n_posts': {
      'free': {
        'enabled': true,
        'limit': 3,
        'period': 'total',
        'requiresAd': false
      },
      'premium': {
        'enabled': false,
        'limit': 0,
        'period': 'total',
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
      invalidateUsageCache();
      rulesRevision.value++;
      debugPrint(
        'PlanLimits live update #${rulesRevision.value} '
        '(features=${_cachedRules?.length ?? 0})',
      );
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

    // Compatibilità: vecchio `import_shared` → nuove chiavi se assenti.
    final legacyImport = rules['import_shared'];
    if (legacyImport is Map) {
      if (rules['import_shared_post'] is! Map) {
        rules['import_shared_post'] = _copyMap(legacyImport);
      }
      if (rules['import_shared_folder'] is! Map) {
        rules['import_shared_folder'] = _copyMap(legacyImport);
      }
    }

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
    // Con live sync attivo la cache è già aggiornata in tempo reale.
    if (!forceRefresh && _cachedRules != null) {
      return _cachedRules!;
    }

    try {
      // forceRefresh legge dal server per evitare regole stale dalla cache locale.
      final doc = await _db.doc('config/plan_limits').get(
            forceRefresh
                ? const GetOptions(source: Source.server)
                : const GetOptions(source: Source.serverAndCache),
          );
      final rules = _mergeWithDefaultRules(
        doc.data()?['featureRules'] as Map<String, dynamic>? ?? {},
      );

      _cachedRules = rules;
      _lastRulesFetch = DateTime.now();
      return rules;
    } catch (e) {
      debugPrint('Error fetching plan limits: $e');
      if (_cachedRules != null) return _cachedRules!;
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

  /// Legge `requiresAd` preferendo la cache live (dashboard → app immediato).
  static Future<bool> featureRequiresAd(String feature) async {
    final role = _auth.currentUser?.effectiveRole ?? AppUserRole.free;
    if (role != AppUserRole.free) return false;

    if (_cachedRules != null) {
      final featureData = _cachedRules![feature];
      if (featureData is Map) {
        final freeRules = featureData['free'];
        if (freeRules is Map) {
          return freeRules['requiresAd'] == true;
        }
      }
    }

    final rule = await getRule(feature, forceRefresh: true);
    return rule.requiresAd;
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

  /// Controlla se un import shared (post e/o cartella) rientra nei limiti.
  /// [posts] = post da importare (1 per post singolo, N per cartella).
  /// [folders] = 1 se importi una cartella root, altrimenti 0.
  /// Restituisce un messaggio utente-friendly con i limiti Free configurati.
  static Future<String?> validateSharedImport({
    required int posts,
    required int folders,
  }) async {
    final usage = await getUsage(forceRefresh: true);
    final postUsage = usage['import_shared_post'];
    final folderUsage = usage['import_shared_folder'];

    String? blockReason;
    if (posts > 0 && postUsage != null) {
      if (!postUsage.enabled) {
        blockReason =
            'L\'importazione post non è disponibile nel piano Free.';
      } else if (!postUsage.isUnlimited &&
          postUsage.count + posts > postUsage.limit) {
        final remaining = postUsage.remaining;
        blockReason = remaining <= 0
            ? 'Hai esaurito gli slot di importazione post.'
            : 'Questa importazione richiede $posts post, ma ti restano solo $remaining slot post.';
      }
    }

    if (blockReason == null && folders > 0 && folderUsage != null) {
      if (!folderUsage.enabled) {
        blockReason =
            'L\'importazione cartelle non è disponibile nel piano Free.';
      } else if (!folderUsage.isUnlimited &&
          folderUsage.count + folders > folderUsage.limit) {
        blockReason = 'Hai esaurito gli slot di importazione cartelle.';
      }
    }

    if (blockReason == null) return null;

    final postLimitLabel = _formatImportLimitLabel(postUsage);
    final folderLimitLabel = _formatImportLimitLabel(folderUsage);
    final needed = StringBuffer();
    if (folders > 0) {
      final folderWord = folders == 1 ? 'cartella' : 'cartelle';
      final postWord = posts == 1 ? 'post' : 'post';
      needed.write(
        'Questa operazione richiede $folders $folderWord e $posts $postWord.',
      );
    } else {
      final postWord = posts == 1 ? 'post' : 'post';
      needed.write('Questa operazione richiede $posts $postWord.');
    }

    return '$blockReason\n\n'
        'Nella versione Free i limiti di importazione sono:\n'
        '• Post: $postLimitLabel\n'
        '• Cartelle: $folderLimitLabel\n\n'
        '$needed\n\n'
        'Passa a Premium per togliere questi limiti.';
  }

  static String _formatImportLimitLabel(PlanFeatureUsage? usage) {
    if (usage == null) return 'non configurato';
    final quota = formatFeatureQuota(
      usage,
      unitSingular:
          usage.feature == 'import_shared_folder' ? 'cartella' : 'post',
      unitPlural:
          usage.feature == 'import_shared_folder' ? 'cartelle' : 'post',
    );
    if (!usage.enabled || usage.isUnlimited) return quota;
    return '$quota (ne restano ${usage.remaining})';
  }

  /// Es. "3 post a settimana", "1 cartella al mese", "illimitati".
  static String formatFeatureQuota(
    PlanFeatureUsage usage, {
    String? unitSingular,
    String? unitPlural,
  }) {
    if (!usage.enabled) return 'disabilitata';
    if (usage.isUnlimited) return 'illimitati';

    final units = _unitsForFeature(usage.feature);
    final singular = unitSingular ?? units.$1;
    final plural = unitPlural ?? units.$2;
    final unit = usage.limit == 1 ? singular : plural;
    final period = periodHumanLabel(usage.period);
    return '${usage.limit} $unit $period';
  }

  static (String, String) _unitsForFeature(String feature) {
    switch (feature) {
      case 'import_shared_post':
      case 'share_post':
        return ('post', 'post');
      case 'import_shared_folder':
      case 'share_folder':
      case 'root_folders':
        return ('cartella', 'cartelle');
      case 'child_folders':
        return ('sottocartella', 'sottocartelle');
      case 'folder_levels':
        return ('livello', 'livelli');
      case 'reminders':
        return ('reminder', 'reminder');
      case 'manual_tags':
        return ('tag', 'tag');
      case 'home_banner_every_n_folders':
      case 'subfolder_banner_every_n_folders':
        return ('cartella', 'cartelle');
      case 'post_banner_every_n_posts':
        return ('post', 'post');
      default:
        return ('utilizzo', 'utilizzi');
    }
  }

  static String periodHumanLabel(String period) {
    switch (period) {
      case 'day':
        return 'al giorno';
      case 'week':
        return 'a settimana';
      case 'month':
        return 'al mese';
      default:
        return 'in totale';
    }
  }

  static String resetHint(PlanFeatureUsage usage) {
    switch (usage.period) {
      case 'day':
        return 'Il limite si resetta domani.';
      case 'week':
        return 'Il limite si resetta lunedì prossimo.';
      case 'month':
        return 'Il limite si resetta il primo del mese prossimo.';
      default:
        return 'Hai raggiunto il limite massimo consentito.';
    }
  }

  /// Frequenza banner tra cartelle (Home e sottocartelle).
  /// Ritorna `null` se i banner sono disabilitati; altrimenti N >= 1.
  static int? homeBannerEveryNFolders() {
    return _bannerEveryN('home_banner_every_n_folders', 3);
  }

  /// Frequenza banner tra i post. Null se disabilitati.
  static int? postBannerEveryNPosts() {
    return _bannerEveryN('post_banner_every_n_posts', 3);
  }

  static int? _bannerEveryN(String featureId, int defaultLimit) {
    final role = _auth.currentUser?.effectiveRole ?? AppUserRole.free;
    if (role != AppUserRole.free) return null;

    Map<String, dynamic>? freeRules;
    final cached = _cachedRules?[featureId];
    if (cached is Map) {
      final free = cached['free'];
      if (free is Map) {
        freeRules = Map<String, dynamic>.from(free);
      }
    }
    freeRules ??= Map<String, dynamic>.from(
      (defaultRules[featureId] as Map<String, dynamic>)['free'] as Map,
    );

    if (freeRules['enabled'] == false) return null;
    final raw = freeRules['limit'];
    final n = raw is int
        ? raw
        : raw is num
            ? raw.toInt()
            : int.tryParse(raw?.toString() ?? '') ?? defaultLimit;
    if (n <= 0) return null;
    return n;
  }

  /// Testo leggibile di una regola tier (Free/Premium) per UI confronto piani.
  static String describeTierRule(String featureId, Map<String, dynamic>? rule) {
    if (rule == null) return 'Non configurato';
    final enabled = rule['enabled'] == true;
    if (!enabled) return 'Non disponibile';

    final rawLimit = rule['limit'];
    final limit = rawLimit is int
        ? rawLimit
        : rawLimit is num
            ? rawLimit.toInt()
            : int.tryParse(rawLimit?.toString() ?? '') ?? 0;
    final period = (rule['period'] ?? 'total').toString();
    final requiresAd = rule['requiresAd'] == true;

    if (featureId == 'home_banner_every_n_folders' ||
        featureId == 'subfolder_banner_every_n_folders') {
      if (limit <= 0) return 'Nessun banner tra le cartelle';
      final base = 'Banner ogni $limit cartelle';
      return requiresAd ? '$base · richiede pubblicità' : base;
    }
    if (featureId == 'post_banner_every_n_posts') {
      if (limit <= 0) return 'Nessun banner tra i post';
      final base = 'Banner ogni $limit post';
      return requiresAd ? '$base · richiede pubblicità' : base;
    }

    if (featureId == 'manual_tags') {
      final base = 'Disponibile';
      return requiresAd ? '$base · richiede pubblicità' : base;
    }

    String quota;
    if (limit <= 0) {
      quota = 'Illimitato';
    } else {
      final units = _unitsForFeature(featureId);
      final unit = limit == 1 ? units.$1 : units.$2;
      quota = '$limit $unit ${periodHumanLabel(period)}';
    }
    if (requiresAd) {
      quota = '$quota · richiede pubblicità';
    }
    return quota;
  }

  /// Confronti Free/Premium per tutte le voci dashboard, dalle regole live.
  static Future<List<({String id, String name, String free, String premium})>>
      buildPlanComparisonRows({bool forceRefresh = true}) async {
    final rules = await getFeatureRules(forceRefresh: forceRefresh);
    return dashboardFeatureCatalog.map((feature) {
      final featureData = rules[feature.id];
      Map<String, dynamic>? free;
      Map<String, dynamic>? premium;
      if (featureData is Map) {
        final freeRaw = featureData['free'];
        final premiumRaw = featureData['premium'];
        if (freeRaw is Map) {
          free = Map<String, dynamic>.from(freeRaw);
        }
        if (premiumRaw is Map) {
          premium = Map<String, dynamic>.from(premiumRaw);
        }
      }
      return (
        id: feature.id,
        name: feature.name,
        free: describeTierRule(feature.id, free),
        premium: describeTierRule(feature.id, premium),
      );
    }).toList();
  }

  /// Testo completo per dialog Free quando una feature ha raggiunto il limite.
  static String reachedLimitMessage({
    required PlanFeatureUsage usage,
    required String featureName,
  }) {
    final quota = formatFeatureQuota(usage);
    return 'Nella versione Free il limite per $featureName è: $quota.\n'
        '${resetHint(usage)}\n\n'
        'Passa a Premium per togliere questo limite.';
  }

  static Future<void> recordSharedImportSuccess({
    required int posts,
    required int folders,
  }) async {
    if (posts > 0) {
      await incrementUsage('import_shared_post', amount: posts);
    }
    if (folders > 0) {
      await incrementUsage('import_shared_folder', amount: folders);
    }
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

  static Future<void> incrementUsage(
    String feature, {
    int amount = 1,
  }) async {
    if (amount <= 0) return;

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
            periodKey: amount,
            'last_update': FieldValue.serverTimestamp(),
          }
        });
      } else {
        final data = doc.data()!;
        final featData = Map<String, dynamic>.from(data[feature] ?? {});
        final currentCount = featData[periodKey] ?? 0;
        featData[periodKey] = currentCount + amount;
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
