import 'package:savein/models/folder.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'interstitial_ad_service.dart';
import 'plan_limits_service.dart';
import '../widgets/free_limit_dialog.dart';

class AppAccessService {
  AppAccessService._internal();

  static final AppAccessService _instance = AppAccessService._internal();

  factory AppAccessService() => _instance;

  // Limiti di fallback (usati se il caricamento dinamico fallisce)
  static const int defaultFreeRootFolderLimit = 10;
  static const int defaultFreeChildFoldersPerParentLimit = 4;
  static const int defaultFreeMaxFolderLevel = 1;
  static const int importInterstitialFrequency = 5;

  final AuthService _authService = AuthService();

  AppUserRole get currentRole =>
      _authService.currentUser?.effectiveRole ?? AppUserRole.free;

  bool get isFree => currentRole == AppUserRole.free;
  bool get isPremium => currentRole == AppUserRole.premium;
  bool get isAdmin => currentRole == AppUserRole.admin;

  bool get hasAds => isFree;

  bool get canManageManualTags {
    final rules = PlanLimitsService.cachedRules;
    if (rules != null && rules['manual_tags'] != null) {
      final tier = isFree ? 'free' : 'premium';
      final tierRule = rules['manual_tags'][tier] as Map<String, dynamic>?;
      if (tierRule != null) {
        return tierRule['enabled'] ?? false;
      }
    }

    // Fallback se non abbiamo cache
    return !isFree;
  }

  bool get canSelfManagePlan => !isAdmin;

  String get currentRoleLabel => roleLabel(currentRole);

  String roleLabel(AppUserRole role) {
    switch (role) {
      case AppUserRole.free:
        return 'Free';
      case AppUserRole.premium:
        return 'Premium';
      case AppUserRole.admin:
        return 'Admin';
    }
  }

  // Nuovi metodi per limiti dinamici
  Future<int> getLimit(String feature) async {
    final rule = await PlanLimitsService.getRule(feature, forceRefresh: true);
    return rule.limit;
  }

  Future<bool> isFeatureEnabled(String feature) async {
    final rule = await PlanLimitsService.getRule(feature, forceRefresh: true);
    return rule.enabled;
  }

  String _limitResetText(PlanFeatureUsage featUsage) {
    if (featUsage.period == 'day') return 'Il limite si resetta domani.';
    if (featUsage.period == 'week') {
      return 'Il limite si resetta lunedì prossimo.';
    }
    if (featUsage.period == 'month') {
      return 'Il limite si resetta il primo del mese prossimo.';
    }
    return 'Hai raggiunto il limite massimo consentito.';
  }

  void _showFreeLimitDialog(
    BuildContext context, {
    required String feature,
    required String featureName,
    required String limitText,
  }) {
    if (!context.mounted) return;
    FreeLimitDialog.show(
      context,
      feature: feature,
      featureName: featureName,
      limitText: limitText,
      isPremium: isPremium,
    );
  }

  Future<bool> checkFeatureAvailable(
    BuildContext context,
    String feature,
    String featureName,
  ) async {
    final usage = await PlanLimitsService.getUsage(forceRefresh: true);
    final featUsage = usage[feature];

    if (featUsage == null) return true;
    if (!featUsage.enabled) {
      _showFreeLimitDialog(
        context,
        feature: feature,
        featureName: featureName,
        limitText:
            'Questa funzione non è disponibile nel tuo piano attuale. Passa a Premium per sbloccarla.',
      );
      return false;
    }
    if (!featUsage.isUnlimited && featUsage.isReached) {
      _showFreeLimitDialog(
        context,
        feature: feature,
        featureName: featureName,
        limitText: _limitResetText(featUsage),
      );
      return false;
    }
    return true;
  }

  Future<void> showAdGateForFeature(BuildContext context, String feature) async {
    if (!context.mounted) return;

    final usage = await PlanLimitsService.getUsage(forceRefresh: true);
    final featUsage = usage[feature];
    if (featUsage == null || !featUsage.requiresAd) return;

    await InterstitialAdService.instance.showFeatureAdGate(context, feature);
  }

  Future<bool> tryConsumeFeature(
      BuildContext context, String feature, String featureName) async {
    final usage = await PlanLimitsService.getUsage(forceRefresh: true);
    final featUsage = usage[feature];

    if (featUsage == null) return true;
    if (!featUsage.enabled) {
      _showFreeLimitDialog(
        context,
        feature: feature,
        featureName: featureName,
        limitText:
            'Questa funzione non è disponibile nel tuo piano attuale. Passa a Premium per sbloccarla.',
      );
      return false;
    }

    if (featUsage.isUnlimited || !featUsage.isReached) {
      await PlanLimitsService.incrementUsage(feature);
      return true;
    }

    _showFreeLimitDialog(
      context,
      feature: feature,
      featureName: featureName,
      limitText: _limitResetText(featUsage),
    );
    return false;
  }

  int countRootFolders(Iterable<MockFolder> folders) {
    return folders
        .where((folder) => !folder.isSpecial && folder.level == 0)
        .length;
  }

  // Nota: Questi metodi rimangono sincroni per compatibilità UI,
  // ma dovrebbero idealmente essere migrati a controlli asincroni o usare dati pre-caricati.
  String? validateRootFolderCreation(Iterable<MockFolder> folders) {
    if (!isFree) return null;

    final rootCount = countRootFolders(folders);
    if (rootCount >= defaultFreeRootFolderLimit) {
      return 'Versione Free: massimo $defaultFreeRootFolderLimit cartelle nella home.';
    }

    return null;
  }

  String? validateRootFolderCreationWithCount(int currentRootCount) {
    if (!isFree) return null;

    if (currentRootCount >= defaultFreeRootFolderLimit) {
      return 'Versione Free: massimo $defaultFreeRootFolderLimit cartelle nella home.';
    }

    return null;
  }

  Future<String?> validateRootFolderCreationWithCountAsync(
    int currentRootCount,
  ) async {
    if (isAdmin) return null;

    try {
      final rule = await PlanLimitsService.getRule(
        'root_folders',
        forceRefresh: true,
      );
      if (!rule.enabled) {
        return 'La creazione di cartelle nella Home è temporaneamente disabilitata.';
      }
      if (rule.limit > 0 && currentRootCount >= rule.limit) {
        return isFree
            ? 'Versione Free: massimo ${rule.limit} cartelle nella home.'
            : 'Massimo ${rule.limit} cartelle nella home.';
      }
      return null;
    } catch (_) {
      return isFree
          ? validateRootFolderCreationWithCount(currentRootCount)
          : null;
    }
  }

  String? validateSubfolderCreation(
    MockFolder parentFolder, {
    int? currentDirectChildrenCount,
  }) {
    if (parentFolder.isSpecial) {
      return 'Non puoi creare sottocartelle in "Tutti".';
    }

    if (isAdmin) return null;

    // Controllo dinamico per Premium
    if (!isFree) {
      // Se abbiamo i limiti in cache, usiamo quelli
      final rules = PlanLimitsService.cachedRules;
      if (rules != null && rules['folder_levels'] != null) {
        final premiumRule =
            rules['folder_levels']['premium'] as Map<String, dynamic>?;
        if (premiumRule != null) {
          final limit = premiumRule['limit'] ?? 0;
          if (limit > 0 && parentFolder.level >= limit - 1) {
            return 'Limite di $limit livelli raggiunto.';
          }
        }
      }

      // Fallback al controllo statico di AppConstants
      if (!parentFolder.canHaveSubfolders) {
        return 'Limite livelli raggiunto.';
      }
      return null;
    }

    if (parentFolder.level >= defaultFreeMaxFolderLevel) {
      return 'Versione Free: puoi creare cartelle solo in home e un livello di profondità.';
    }

    final directChildrenCount = currentDirectChildrenCount ??
        parentFolder.children.where((child) => !child.isSpecial).length;
    if (directChildrenCount >= defaultFreeChildFoldersPerParentLimit) {
      return 'Versione Free: massimo $defaultFreeChildFoldersPerParentLimit sottocartelle per cartella.';
    }

    return null;
  }

  Future<String?> validateSubfolderCreationAsync(
    MockFolder parentFolder, {
    int? currentDirectChildrenCount,
  }) async {
    if (parentFolder.isSpecial) {
      return 'Non puoi creare sottocartelle in "Tutti".';
    }
    if (isAdmin) return null;

    try {
      final levelRule = await PlanLimitsService.getRule(
        'folder_levels',
        forceRefresh: true,
      );
      if (!levelRule.enabled) {
        return 'La creazione di nuovi livelli di cartelle è temporaneamente disabilitata.';
      }
      if (levelRule.limit > 0 && parentFolder.level >= levelRule.limit - 1) {
        return isFree
            ? 'Versione Free: massimo ${levelRule.limit} livelli di profondità.'
            : 'Limite di ${levelRule.limit} livelli raggiunto.';
      }

      final childRule = await PlanLimitsService.getRule(
        'child_folders',
        forceRefresh: true,
      );
      if (!childRule.enabled) {
        return 'La creazione di sottocartelle è temporaneamente disabilitata.';
      }
      final directChildrenCount = currentDirectChildrenCount ??
          parentFolder.children.where((child) => !child.isSpecial).length;
      if (childRule.limit > 0 && directChildrenCount >= childRule.limit) {
        return isFree
            ? 'Versione Free: massimo ${childRule.limit} sottocartelle per cartella.'
            : 'Massimo ${childRule.limit} sottocartelle per cartella.';
      }

      return null;
    } catch (_) {
      return validateSubfolderCreation(
        parentFolder,
        currentDirectChildrenCount: currentDirectChildrenCount,
      );
    }
  }

  Future<String?> validateChildFolderCountForCreationAsync(
    int currentDirectChildrenCount,
  ) async {
    if (isAdmin) return null;

    try {
      final rule = await PlanLimitsService.getRule(
        'child_folders',
        forceRefresh: true,
      );
      if (!rule.enabled) {
        return 'La creazione di sottocartelle è temporaneamente disabilitata.';
      }
      if (rule.limit > 0 && currentDirectChildrenCount >= rule.limit) {
        return isFree
            ? 'Versione Free: massimo ${rule.limit} sottocartelle per cartella.'
            : 'Massimo ${rule.limit} sottocartelle per cartella.';
      }
      return null;
    } catch (_) {
      if (isFree &&
          currentDirectChildrenCount >= defaultFreeChildFoldersPerParentLimit) {
        return 'Versione Free: massimo $defaultFreeChildFoldersPerParentLimit sottocartelle per cartella.';
      }
      return null;
    }
  }

  String? validateHierarchyDepthForCreation(int pathLength) {
    if (!isFree) return null;

    if (pathLength > defaultFreeMaxFolderLevel + 1) {
      return 'Versione Free: puoi creare cartelle solo in home e un livello di profondità.';
    }

    return null;
  }

  Future<String?> validateHierarchyDepthForCreationAsync(int pathLength) async {
    if (isAdmin) return null;

    try {
      final rule = await PlanLimitsService.getRule(
        'folder_levels',
        forceRefresh: true,
      );
      if (!rule.enabled) {
        return 'La creazione di nuovi livelli di cartelle è temporaneamente disabilitata.';
      }
      if (rule.limit > 0 && pathLength > rule.limit) {
        return isFree
            ? 'Versione Free: massimo ${rule.limit} livelli di profondità.'
            : 'Massimo ${rule.limit} livelli di profondità.';
      }
      return null;
    } catch (_) {
      return isFree ? validateHierarchyDepthForCreation(pathLength) : null;
    }
  }

  String? validateFolderDestination(MockFolder? folder) {
    if (!isFree || folder == null || folder.isSpecial) return null;

    if (folder.level > defaultFreeMaxFolderLevel) {
      return 'Versione Free: puoi salvare solo in home o in cartelle di primo livello.';
    }

    return null;
  }

  Future<String?> validateFolderDestinationAsync(MockFolder? folder) async {
    if (isAdmin || folder == null || folder.isSpecial) return null;

    try {
      final rule = await PlanLimitsService.getRule(
        'folder_levels',
        forceRefresh: true,
      );
      if (!rule.enabled) {
        return 'Il salvataggio in sottocartelle è temporaneamente disabilitato.';
      }
      if (rule.limit > 0 && folder.level >= rule.limit) {
        return isFree
            ? 'Versione Free: puoi salvare fino a ${rule.limit} livelli di profondità.'
            : 'Puoi salvare fino a ${rule.limit} livelli di profondità.';
      }
      return null;
    } catch (_) {
      return isFree ? validateFolderDestination(folder) : null;
    }
  }

  int cachedMaxFolderLevelsForCurrentTier() {
    final fallback = isFree ? defaultFreeMaxFolderLevel + 1 : 0;
    final rules = PlanLimitsService.cachedRules;
    if (rules == null || rules['folder_levels'] == null) return fallback;
    final tier = isFree ? 'free' : 'premium';
    final featureRules = Map<String, dynamic>.from(rules['folder_levels']);
    final tierRule = featureRules[tier] is Map
        ? Map<String, dynamic>.from(featureRules[tier])
        : null;
    if (tierRule == null) return fallback;
    return (tierRule['limit'] as num?)?.toInt() ?? fallback;
  }
}
