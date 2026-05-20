import '../models/folder.dart';
import 'auth_service.dart';

class AppAccessService {
  AppAccessService._internal();

  static final AppAccessService _instance = AppAccessService._internal();

  factory AppAccessService() => _instance;

  static const int freeRootFolderLimit = 10;
  static const int freeChildFoldersPerParentLimit = 4;
  static const int freeMaxFolderLevel = 1; // Home (0) + un livello (1)
  static const int importInterstitialFrequency = 5;

  final AuthService _authService = AuthService();

  AppUserRole get currentRole =>
      _authService.currentUser?.effectiveRole ?? AppUserRole.free;

  bool get isFree => currentRole == AppUserRole.free;
  bool get isPremium => currentRole == AppUserRole.premium;
  bool get isAdmin => currentRole == AppUserRole.admin;

  bool get hasAds => isFree;
  bool get canManageManualTags => !isFree;
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

  int countRootFolders(Iterable<MockFolder> folders) {
    return folders
        .where((folder) => !folder.isSpecial && folder.level == 0)
        .length;
  }

  String? validateRootFolderCreation(Iterable<MockFolder> folders) {
    if (!isFree) return null;

    final rootCount = countRootFolders(folders);
    if (rootCount >= freeRootFolderLimit) {
      return 'Versione Free: massimo $freeRootFolderLimit cartelle nella home.';
    }

    return null;
  }

  String? validateRootFolderCreationWithCount(int currentRootCount) {
    if (!isFree) return null;

    if (currentRootCount >= freeRootFolderLimit) {
      return 'Versione Free: massimo $freeRootFolderLimit cartelle nella home.';
    }

    return null;
  }

  String? validateSubfolderCreation(
    MockFolder parentFolder, {
    int? currentDirectChildrenCount,
  }) {
    if (parentFolder.isSpecial) {
      return 'Non puoi creare sottocartelle in "Tutti".';
    }

    if (!isFree) {
      if (!parentFolder.canHaveSubfolders) {
        return 'Limite livelli raggiunto.';
      }
      return null;
    }

    if (parentFolder.level >= freeMaxFolderLevel) {
      return 'Versione Free: puoi creare cartelle solo in home e un livello di profondità.';
    }

    final directChildrenCount = currentDirectChildrenCount ??
        parentFolder.children.where((child) => !child.isSpecial).length;
    if (directChildrenCount >= freeChildFoldersPerParentLimit) {
      return 'Versione Free: massimo $freeChildFoldersPerParentLimit sottocartelle per cartella.';
    }

    return null;
  }

  String? validateHierarchyDepthForCreation(int pathLength) {
    if (!isFree) return null;

    if (pathLength > freeMaxFolderLevel + 1) {
      return 'Versione Free: puoi creare cartelle solo in home e un livello di profondità.';
    }

    return null;
  }

  String? validateFolderDestination(MockFolder? folder) {
    if (!isFree || folder == null || folder.isSpecial) return null;

    if (folder.level > freeMaxFolderLevel) {
      return 'Versione Free: puoi salvare solo in home o in cartelle di primo livello.';
    }

    return null;
  }
}
