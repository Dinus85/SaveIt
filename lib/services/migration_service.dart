// lib/services/migration_service.dart
// Service per migrazione one-time da SharedPreferences a Firebase Firestore
// Fase 7: Testing e migrazione dati - Sistema di migrazione enterprise

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:savein/data_service.dart';
import 'package:savein/models.dart';
import '../services/auth_service.dart';

/// Status della migrazione
enum MigrationStatus {
  notStarted,
  detecting,
  validating,
  migrating,
  completed,
  failed,
  rolledBack
}

/// Risultato della migrazione
class MigrationResult {
  final bool success;
  final MigrationStatus status;
  final String? errorMessage;
  final Map<String, dynamic> statistics;
  final DateTime timestamp;

  MigrationResult({
    required this.success,
    required this.status,
    this.errorMessage,
    required this.statistics,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'status': status.toString(),
      'errorMessage': errorMessage,
      'statistics': statistics,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Progresso della migrazione in tempo reale
class MigrationProgress {
  final MigrationStatus status;
  final String currentStep;
  final int completedSteps;
  final int totalSteps;
  final double progressPercentage;
  final String? currentItem;

  MigrationProgress({
    required this.status,
    required this.currentStep,
    required this.completedSteps,
    required this.totalSteps,
    required this.progressPercentage,
    this.currentItem,
  });
}

/// Dati legacy trovati in SharedPreferences
class LegacyData {
  final List<Map<String, dynamic>> folders;
  final List<Map<String, dynamic>> posts;
  final Map<String, dynamic> metadata;
  final DateTime detectedAt;

  LegacyData({
    required this.folders,
    required this.posts,
    required this.metadata,
    required this.detectedAt,
  });

  int get totalItems => folders.length + posts.length;
  bool get isEmpty => folders.isEmpty && posts.isEmpty;
}

/// Exception per errori di migrazione
class MigrationException implements Exception {
  final String message;
  final String? step;
  final dynamic originalError;

  MigrationException(this.message, {this.step, this.originalError});

  @override
  String toString() =>
      'MigrationException: $message${step != null ? ' (step: $step)' : ''}';
}

/// Servizio principale per migrazione da SharedPreferences a Firebase
/// Gestisce tutto il processo di migrazione con backup, validazione e rollback
class MigrationService extends ChangeNotifier {
  static final MigrationService _instance = MigrationService._internal();
  factory MigrationService() => _instance;
  MigrationService._internal();

  // Stream controller per progresso real-time
  final StreamController<MigrationProgress> _progressController =
      StreamController<MigrationProgress>.broadcast();

  // Servizi dependencies
  final AuthService _authService = AuthService();
  final DataService _dataService = DataService.instance;

  // Stato migrazione
  MigrationStatus _currentStatus = MigrationStatus.notStarted;
  MigrationProgress? _lastProgress;
  LegacyData? _detectedLegacyData;
  String? _backupKey;

  // Constants
  static const String _migrationCompletedKey = 'migration_completed_v1';
  static const String _backupPrefix = 'migration_backup_';
  static const String _legacyFoldersKey = 'folders';
  static const String _legacyPostsKey = 'all_posts';
  static const String _legacyStatsKey = 'app_statistics';

  /// Stream per seguire il progresso in tempo reale
  Stream<MigrationProgress> get progressStream => _progressController.stream;

  /// Status corrente della migrazione
  MigrationStatus get currentStatus => _currentStatus;

  /// Dati legacy rilevati
  LegacyData? get detectedLegacyData => _detectedLegacyData;

  /// Getter per verifiche autenticazione
  bool get _isUserAuthenticated => _authService.isLoggedIn;
  String? get _currentUserId => _authService.currentUser?.id;

  // ============================================================================
  // METODI PUBBLICI PRINCIPALI
  // ============================================================================

  /// Verifica se la migrazione è già stata completata
  Future<bool> isMigrationCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isCompleted = prefs.getBool(_migrationCompletedKey) ?? false;

      print('DEBUG: Migration - Verifica stato completamento: $isCompleted');
      return isCompleted;
    } catch (e) {
      print('ERRORE: Migration - Verifica stato fallita: $e');
      return false;
    }
  }

  /// Rileva se esistono dati legacy da migrare
  Future<LegacyData?> detectLegacyData() async {
    try {
      _updateProgress(
          MigrationStatus.detecting, 'Rilevamento dati legacy...', 0, 3);

      final prefs = await SharedPreferences.getInstance();

      // Rileva cartelle legacy
      final foldersJson = prefs.getString(_legacyFoldersKey);
      List<Map<String, dynamic>> legacyFolders = [];

      if (foldersJson != null) {
        try {
          final foldersList = jsonDecode(foldersJson) as List;
          legacyFolders = foldersList.cast<Map<String, dynamic>>();
        } catch (e) {
          print('WARNING: Migration - Errore parsing folders legacy: $e');
        }
      }

      _updateProgress(
          MigrationStatus.detecting, 'Rilevamento post legacy...', 1, 3);

      // Rileva post legacy
      final postsJson = prefs.getString(_legacyPostsKey);
      List<Map<String, dynamic>> legacyPosts = [];

      if (postsJson != null) {
        try {
          final postsList = jsonDecode(postsJson) as List;
          legacyPosts = postsList.cast<Map<String, dynamic>>();
        } catch (e) {
          print('WARNING: Migration - Errore parsing posts legacy: $e');
        }
      }

      _updateProgress(
          MigrationStatus.detecting, 'Rilevamento metadati...', 2, 3);

      // Rileva metadati legacy
      final statsJson = prefs.getString(_legacyStatsKey);
      Map<String, dynamic> metadata = {};

      if (statsJson != null) {
        try {
          metadata = jsonDecode(statsJson) as Map<String, dynamic>;
        } catch (e) {
          print('WARNING: Migration - Errore parsing stats legacy: $e');
        }
      }

      // Crea oggetto dati legacy
      final legacyData = LegacyData(
        folders: legacyFolders,
        posts: legacyPosts,
        metadata: metadata,
        detectedAt: DateTime.now(),
      );

      _detectedLegacyData = legacyData;

      _updateProgress(
          MigrationStatus.detecting, 'Rilevamento completato', 3, 3);

      print(
          'DEBUG: Migration - Dati legacy rilevati: ${legacyData.folders.length} folders, ${legacyData.posts.length} posts');

      return legacyData.isEmpty ? null : legacyData;
    } catch (e) {
      print('ERRORE: Migration - Rilevamento dati legacy fallito: $e');
      throw MigrationException(
        'Impossibile rilevare dati legacy: $e',
        step: 'detection',
        originalError: e,
      );
    }
  }

  /// Esegue la migrazione completa con backup e validazione
  Future<MigrationResult> performMigration() async {
    final startTime = DateTime.now();
    final statistics = <String, dynamic>{};

    try {
      // STEP 1: Verifiche preliminari
      await _performPreMigrationChecks();

      // STEP 2: Rilevamento dati
      final legacyData = await detectLegacyData();
      if (legacyData == null || legacyData.isEmpty) {
        return _createSuccessResult(
            statistics, 'Nessun dato legacy da migrare');
      }

      statistics['legacy_folders_found'] = legacyData.folders.length;
      statistics['legacy_posts_found'] = legacyData.posts.length;

      // STEP 3: Backup dati esistenti
      await _createBackup(legacyData);

      // STEP 4: Validazione dati legacy
      final validatedData = await _validateLegacyData(legacyData);
      statistics['valid_folders'] = validatedData.folders.length;
      statistics['valid_posts'] = validatedData.posts.length;

      // STEP 5: Migrazione cartelle
      final migratedFolders = await _migrateFolders(validatedData.folders);
      statistics['migrated_folders'] = migratedFolders.length;

      // STEP 6: Migrazione post
      final migratedPosts =
          await _migratePosts(validatedData.posts, migratedFolders);
      statistics['migrated_posts'] = migratedPosts.length;

      // STEP 7: Validazione post-migrazione
      await _validateMigration(migratedFolders, migratedPosts);

      // STEP 8: Cleanup e finalizzazione
      await _finalizeMigration(legacyData);

      final duration = DateTime.now().difference(startTime);
      statistics['migration_duration_ms'] = duration.inMilliseconds;
      statistics['migration_completed_at'] = DateTime.now().toIso8601String();

      _currentStatus = MigrationStatus.completed;

      return _createSuccessResult(
          statistics, 'Migrazione completata con successo');
    } catch (e) {
      print('ERRORE: Migration - Migrazione fallita: $e');

      // Tentativo di rollback automatico
      try {
        await _performRollback();
        _currentStatus = MigrationStatus.rolledBack;
        statistics['rollback_performed'] = true;
      } catch (rollbackError) {
        print('ERRORE: Migration - Rollback fallito: $rollbackError');
        _currentStatus = MigrationStatus.failed;
        statistics['rollback_failed'] = true;
      }

      final duration = DateTime.now().difference(startTime);
      statistics['failed_duration_ms'] = duration.inMilliseconds;

      return MigrationResult(
        success: false,
        status: _currentStatus,
        errorMessage: e.toString(),
        statistics: statistics,
        timestamp: DateTime.now(),
      );
    }
  }

  /// Rollback manuale in caso di problemi
  Future<void> performRollback() async {
    try {
      print('DEBUG: Migration - Iniziando rollback manuale...');
      await _performRollback();
      _currentStatus = MigrationStatus.rolledBack;
    } catch (e) {
      print('ERRORE: Migration - Rollback manuale fallito: $e');
      _currentStatus = MigrationStatus.failed;
      rethrow;
    }
  }

  /// Pulisce tutti i dati legacy dopo migrazione confermata
  Future<void> cleanupLegacyData() async {
    try {
      print('DEBUG: Migration - Pulizia dati legacy...');

      final prefs = await SharedPreferences.getInstance();

      // Rimuovi dati legacy
      await prefs.remove(_legacyFoldersKey);
      await prefs.remove(_legacyPostsKey);
      await prefs.remove(_legacyStatsKey);

      // Rimuovi backup se presente
      if (_backupKey != null) {
        await prefs.remove(_backupKey!);
      }

      print('DEBUG: Migration - Dati legacy puliti');
    } catch (e) {
      print('ERRORE: Migration - Pulizia dati legacy fallita: $e');
      throw MigrationException(
        'Impossibile pulire dati legacy: $e',
        step: 'cleanup',
        originalError: e,
      );
    }
  }

  // ============================================================================
  // METODI PRIVATI DI IMPLEMENTAZIONE
  // ============================================================================

  Future<void> _performPreMigrationChecks() async {
    _updateProgress(
        MigrationStatus.validating, 'Verifiche preliminari...', 0, 10);

    // Verifica autenticazione
    if (!_isUserAuthenticated) {
      throw MigrationException(
        'Utente non autenticato. È richiesto il login per la migrazione.',
        step: 'pre_checks',
      );
    }

    // Verifica se migrazione già completata
    if (await isMigrationCompleted()) {
      throw MigrationException(
        'Migrazione già completata per questo dispositivo.',
        step: 'pre_checks',
      );
    }

    // Verifica DataService
    try {
      await _dataService.initializeDefaultData();
    } catch (e) {
      throw MigrationException(
        'Impossibile inizializzare DataService: $e',
        step: 'pre_checks',
        originalError: e,
      );
    }

    print('DEBUG: Migration - Verifiche preliminari completate');
  }

  Future<void> _createBackup(LegacyData legacyData) async {
    _updateProgress(MigrationStatus.migrating, 'Creazione backup...', 1, 10);

    try {
      final prefs = await SharedPreferences.getInstance();
      _backupKey = '$_backupPrefix${DateTime.now().millisecondsSinceEpoch}';

      final backupData = {
        'folders': legacyData.folders,
        'posts': legacyData.posts,
        'metadata': legacyData.metadata,
        'backup_created_at': legacyData.detectedAt.toIso8601String(),
        'user_id': _currentUserId,
      };

      await prefs.setString(_backupKey!, jsonEncode(backupData));

      print('DEBUG: Migration - Backup creato con chiave: $_backupKey');
    } catch (e) {
      throw MigrationException(
        'Impossibile creare backup: $e',
        step: 'backup',
        originalError: e,
      );
    }
  }

  Future<LegacyData> _validateLegacyData(LegacyData legacyData) async {
    _updateProgress(MigrationStatus.migrating, 'Validazione dati...', 2, 10);

    final validFolders = <Map<String, dynamic>>[];
    final validPosts = <Map<String, dynamic>>[];

    // Valida cartelle
    for (var folderData in legacyData.folders) {
      try {
        // Verifica campi obbligatori
        if (folderData['name'] != null &&
            folderData['name'].toString().trim().isNotEmpty) {
          // Normalizza dati cartella
          final normalizedFolder = {
            'name': folderData['name'].toString().trim(),
            'color': folderData['color'] ?? '#BB86FC',
            'level': folderData['level'] ?? 0,
            'isSpecial': folderData['isSpecial'] ?? false,
            'created_at': DateTime.now().toIso8601String(),
          };

          validFolders.add(normalizedFolder);
        }
      } catch (e) {
        print('WARNING: Migration - Cartella invalida ignorata: $e');
      }
    }

    // Valida post
    for (var postData in legacyData.posts) {
      try {
        // Verifica campi obbligatori
        if (postData['url'] != null &&
            postData['title'] != null &&
            postData['url'].toString().trim().isNotEmpty &&
            postData['title'].toString().trim().isNotEmpty) {
          // Normalizza dati post
          final normalizedPost = {
            'url': postData['url'].toString().trim(),
            'title': postData['title'].toString().trim(),
            'description': postData['description']?.toString() ?? '',
            'imageUrl': postData['imageUrl']?.toString(),
            'tags': postData['tags'] ?? [],
            'savedDate':
                postData['savedDate'] ?? DateTime.now().toIso8601String(),
            'sourceFolder': postData['sourceFolder'],
          };

          validPosts.add(normalizedPost);
        }
      } catch (e) {
        print('WARNING: Migration - Post invalido ignorato: $e');
      }
    }

    print(
        'DEBUG: Migration - Validazione completata: ${validFolders.length}/${legacyData.folders.length} folders, ${validPosts.length}/${legacyData.posts.length} posts');

    return LegacyData(
      folders: validFolders,
      posts: validPosts,
      metadata: legacyData.metadata,
      detectedAt: legacyData.detectedAt,
    );
  }

  Future<Map<String, Folder>> _migrateFolders(
      List<Map<String, dynamic>> legacyFolders) async {
    _updateProgress(MigrationStatus.migrating, 'Migrazione cartelle...', 3, 10);

    final migratedFolders = <String, Folder>{};

    for (int i = 0; i < legacyFolders.length; i++) {
      final folderData = legacyFolders[i];

      try {
        _updateProgress(
          MigrationStatus.migrating,
          'Migrazione cartelle...',
          3,
          10,
          currentItem: 'Cartella: ${folderData['name']}',
        );

        // Crea cartella in Firebase
        final newFolder = await _dataService.createFolder(
          name: folderData['name'],
          color: folderData['color'],
        );

        migratedFolders[folderData['name']] = newFolder;

        print(
            'DEBUG: Migration - Cartella migrata: ${newFolder.name} (ID: ${newFolder.id})');
      } catch (e) {
        print(
            'ERRORE: Migration - Migrazione cartella fallita: ${folderData['name']} - $e');
        // Continua con le altre cartelle
      }
    }

    return migratedFolders;
  }

  Future<List<SavedPost>> _migratePosts(
    List<Map<String, dynamic>> legacyPosts,
    Map<String, Folder> migratedFolders,
  ) async {
    _updateProgress(MigrationStatus.migrating, 'Migrazione post...', 5, 10);

    final migratedPosts = <SavedPost>[];

    // Trova cartella "Tutti" come default
    final allFolders = await _dataService.getFolders();
    final defaultFolder = allFolders.firstWhere(
      (f) => f.isDefault,
      orElse: () => throw MigrationException('Cartella "Tutti" non trovata'),
    );

    for (int i = 0; i < legacyPosts.length; i++) {
      final postData = legacyPosts[i];

      try {
        _updateProgress(
          MigrationStatus.migrating,
          'Migrazione post...',
          5,
          10,
          currentItem: 'Post: ${postData['title']}',
        );

        // Determina cartella di destinazione
        String targetFolderId = defaultFolder.id;

        final sourceFolderName = postData['sourceFolder']?['name'];
        if (sourceFolderName != null &&
            migratedFolders.containsKey(sourceFolderName)) {
          targetFolderId = migratedFolders[sourceFolderName]!.id;
        }

        // Converti data di salvataggio
        DateTime savedDate = DateTime.now();
        try {
          if (postData['savedDate'] != null) {
            savedDate = DateTime.parse(postData['savedDate']);
          }
        } catch (e) {
          print('WARNING: Migration - Data invalida per post, usando corrente');
        }

        // Converti tags
        List<String> tags = [];
        try {
          if (postData['tags'] != null) {
            tags = List<String>.from(postData['tags']);
          }
        } catch (e) {
          print(
              'WARNING: Migration - Tags invalidi per post, usando lista vuota');
        }

        // Crea post in Firebase
        final newPost = await _dataService.createPost(
          url: postData['url'],
          title: postData['title'],
          description: postData['description'] ?? '',
          imageUrl: postData['imageUrl'],
          creatorName: postData['creatorName'],
          creatorUsername: postData['creatorUsername'],
          tags: tags,
          folderId: targetFolderId,
        );

        migratedPosts.add(newPost);

        print(
            'DEBUG: Migration - Post migrato: ${newPost.title} (ID: ${newPost.id})');
      } catch (e) {
        print(
            'ERRORE: Migration - Migrazione post fallita: ${postData['title']} - $e');
        // Continua con gli altri post
      }
    }

    return migratedPosts;
  }

  Future<void> _validateMigration(
    Map<String, Folder> migratedFolders,
    List<SavedPost> migratedPosts,
  ) async {
    _updateProgress(
        MigrationStatus.migrating, 'Validazione migrazione...', 8, 10);

    try {
      // Verifica cartelle in Firebase
      final cloudFolders = await _dataService.getFolders();
      for (final folder in migratedFolders.values) {
        if (!cloudFolders.any((f) => f.id == folder.id)) {
          throw MigrationException(
              'Cartella non trovata in Firebase: ${folder.name}');
        }
      }

      // Verifica post in Firebase
      final cloudPosts = await _dataService.getPosts();
      for (final post in migratedPosts) {
        if (!cloudPosts.any((p) => p.id == post.id)) {
          throw MigrationException(
              'Post non trovato in Firebase: ${post.title}');
        }
      }

      print(
          'DEBUG: Migration - Validazione migrazione completata con successo');
    } catch (e) {
      throw MigrationException(
        'Validazione migrazione fallita: $e',
        step: 'validation',
        originalError: e,
      );
    }
  }

  Future<void> _finalizeMigration(LegacyData legacyData) async {
    _updateProgress(MigrationStatus.migrating, 'Finalizzazione...', 9, 10);

    try {
      final prefs = await SharedPreferences.getInstance();

      // Marca migrazione come completata
      await prefs.setBool(_migrationCompletedKey, true);

      // Salva statistiche migrazione
      final migrationStats = {
        'completed_at': DateTime.now().toIso8601String(),
        'user_id': _currentUserId,
        'folders_migrated': legacyData.folders.length,
        'posts_migrated': legacyData.posts.length,
        'backup_key': _backupKey,
      };

      await prefs.setString('migration_stats', jsonEncode(migrationStats));

      print('DEBUG: Migration - Finalizzazione completata');
    } catch (e) {
      throw MigrationException(
        'Impossibile finalizzare migrazione: $e',
        step: 'finalization',
        originalError: e,
      );
    }

    _updateProgress(
        MigrationStatus.completed, 'Migrazione completata!', 10, 10);
  }

  Future<void> _performRollback() async {
    print('DEBUG: Migration - Eseguendo rollback...');

    try {
      if (_backupKey == null) {
        throw MigrationException('Nessun backup disponibile per rollback');
      }

      final prefs = await SharedPreferences.getInstance();
      final backupJson = prefs.getString(_backupKey!);

      if (backupJson == null) {
        throw MigrationException('Backup non trovato: $_backupKey');
      }

      final backupData = jsonDecode(backupJson) as Map<String, dynamic>;

      // Ripristina dati legacy
      if (backupData['folders'] != null) {
        await prefs.setString(
            _legacyFoldersKey, jsonEncode(backupData['folders']));
      }

      if (backupData['posts'] != null) {
        await prefs.setString(_legacyPostsKey, jsonEncode(backupData['posts']));
      }

      if (backupData['metadata'] != null) {
        await prefs.setString(
            _legacyStatsKey, jsonEncode(backupData['metadata']));
      }

      // Rimuovi flag completamento
      await prefs.remove(_migrationCompletedKey);

      print('DEBUG: Migration - Rollback completato');
    } catch (e) {
      print('ERRORE: Migration - Rollback fallito: $e');
      rethrow;
    }
  }

  void _updateProgress(
    MigrationStatus status,
    String step,
    int completed,
    int total, {
    String? currentItem,
  }) {
    _currentStatus = status;

    final progress = MigrationProgress(
      status: status,
      currentStep: step,
      completedSteps: completed,
      totalSteps: total,
      progressPercentage: total > 0 ? (completed / total) * 100 : 0,
      currentItem: currentItem,
    );

    _lastProgress = progress;
    _progressController.add(progress);

    print(
        'DEBUG: Migration Progress - $step (${completed}/${total}) ${currentItem ?? ''}');
  }

  MigrationResult _createSuccessResult(
      Map<String, dynamic> statistics, String message) {
    return MigrationResult(
      success: true,
      status: MigrationStatus.completed,
      errorMessage: null,
      statistics: statistics,
      timestamp: DateTime.now(),
    );
  }

  // ============================================================================
  // UTILITY E DEBUG
  // ============================================================================

  /// Informazioni diagnostiche per troubleshooting
  Future<Map<String, dynamic>> getDiagnosticInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      return {
        'migration_service_status': _currentStatus.toString(),
        'user_authenticated': _isUserAuthenticated,
        'user_id': _currentUserId,
        'migration_completed': await isMigrationCompleted(),
        'backup_key': _backupKey,
        'detected_legacy_data': _detectedLegacyData != null
            ? {
                'folders_count': _detectedLegacyData!.folders.length,
                'posts_count': _detectedLegacyData!.posts.length,
                'detected_at':
                    _detectedLegacyData!.detectedAt.toIso8601String(),
              }
            : null,
        'shared_preferences_keys': prefs.getKeys().toList(),
        'last_progress': _lastProgress != null
            ? {
                'status': _lastProgress!.status.toString(),
                'step': _lastProgress!.currentStep,
                'progress': _lastProgress!.progressPercentage,
              }
            : null,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Reset completo per testing
  Future<void> resetMigrationState() async {
    try {
      print('DEBUG: Migration - Reset stato migrazione...');

      final prefs = await SharedPreferences.getInstance();

      // Rimuovi flag completamento
      await prefs.remove(_migrationCompletedKey);

      // Rimuovi backup
      if (_backupKey != null) {
        await prefs.remove(_backupKey!);
      }

      // Reset stato interno
      _currentStatus = MigrationStatus.notStarted;
      _detectedLegacyData = null;
      _backupKey = null;
      _lastProgress = null;

      print('DEBUG: Migration - Reset completato');
    } catch (e) {
      print('ERRORE: Migration - Reset fallito: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _progressController.close();
    super.dispose();
  }
}
