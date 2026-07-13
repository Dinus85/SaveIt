// lib/models.dart
// Modelli con estensioni Firestore - Fase 4 completata
// FIXED: Rimosse duplicazioni e import circolari

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:savein/models/folder.dart' show MockFolder;

// ============================================================================
// SAVED POST
// ============================================================================

class SavedPost {
  final String id;
  final String url;
  final String title;
  final String description;
  final String? imageUrl;
  final String? creatorName;
  final String? creatorUsername;

  /// URL dell'anteprima salvata in remoto (es. Firebase Storage).
  /// Usato per anteprime "stabili" (es. Instagram) quando `imageUrl` scade o non è accessibile.
  final String? previewStorageUrl;
  final List<String> tags;
  final String folderId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isShared; // 🆕 NUOVO: Indica se il post è condiviso
  final String? globalPostId;
  final String? urlHash;
  final String? normalizedUrl;

  SavedPost({
    required this.id,
    required this.url,
    required this.title,
    required this.description,
    this.imageUrl,
    this.creatorName,
    this.creatorUsername,
    this.previewStorageUrl,
    required this.tags,
    required this.folderId,
    required this.createdAt,
    this.updatedAt,
    this.isShared = false,
    this.globalPostId,
    this.urlHash,
    this.normalizedUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'creatorName': creatorName,
      'creatorUsername': creatorUsername,
      'previewStorageUrl': previewStorageUrl,
      'tags': tags,
      'folderId': folderId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'isShared': isShared,
      'globalPostId': globalPostId,
      'urlHash': urlHash,
      'normalizedUrl': normalizedUrl,
    };
  }

  factory SavedPost.fromJson(Map<String, dynamic> json) {
    return SavedPost(
      id: json['id'] ?? '',
      url: json['url'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      imageUrl: json['imageUrl'],
      creatorName: json['creatorName'],
      creatorUsername: json['creatorUsername'],
      previewStorageUrl: json['previewStorageUrl'],
      tags: List<String>.from(json['tags'] ?? []),
      folderId: json['folderId'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt:
          json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
      isShared: json['isShared'] ?? false,
      globalPostId: json['globalPostId'],
      urlHash: json['urlHash'],
      normalizedUrl: json['normalizedUrl'],
    );
  }

  SavedPost copyWith({
    String? id,
    String? url,
    String? title,
    String? description,
    String? imageUrl,
    String? creatorName,
    String? creatorUsername,
    String? previewStorageUrl,
    List<String>? tags,
    String? folderId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isShared,
    String? globalPostId,
    String? urlHash,
    String? normalizedUrl,
  }) {
    return SavedPost(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      creatorName: creatorName ?? this.creatorName,
      creatorUsername: creatorUsername ?? this.creatorUsername,
      previewStorageUrl: previewStorageUrl ?? this.previewStorageUrl,
      tags: tags ?? this.tags,
      folderId: folderId ?? this.folderId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isShared: isShared ?? this.isShared,
      globalPostId: globalPostId ?? this.globalPostId,
      urlHash: urlHash ?? this.urlHash,
      normalizedUrl: normalizedUrl ?? this.normalizedUrl,
    );
  }

  MockPost toMockPost({MockFolder? targetFolder}) {
    return MockPost(
      id: id,
      title: title,
      url: url,
      description: description,
      savedDate: createdAt,
      sourceFolder: targetFolder,
      tags: List<String>.from(tags),
      imageUrl: imageUrl,
      creatorName: creatorName,
      creatorUsername: creatorUsername,
      previewStorageUrl: previewStorageUrl,
      isShared: isShared,
    );
  }

  bool get isValid {
    return id.isNotEmpty &&
        url.isNotEmpty &&
        title.isNotEmpty &&
        folderId.isNotEmpty &&
        _isValidUrl(url);
  }

  bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  String get displayTitle => title.isNotEmpty ? title : description;
  String get displayDescription =>
      description.isNotEmpty ? description : 'Nessuna descrizione disponibile';
}

// ============================================================================
// MOCK POST
// ============================================================================

class MockPost {
  final String id;
  final String title;
  final String url;
  final String description;
  final DateTime savedDate;
  final MockFolder? sourceFolder;
  List<String> tags;
  final String? imageUrl;
  final String? creatorName;
  final String? creatorUsername;
  final String? previewStorageUrl;
  final bool isShared; // 🆕 NUOVO: Indica se il post è stato condiviso

  MockPost({
    required this.id,
    required this.title,
    required this.url,
    required this.description,
    required this.savedDate,
    this.sourceFolder,
    List<String>? tags,
    this.imageUrl,
    this.creatorName,
    this.creatorUsername,
    this.previewStorageUrl,
    this.isShared = false,
  }) : tags = tags ?? [];

  SavedPost toSavedPost() {
    return SavedPost(
      id: id,
      url: url,
      title: title,
      description: description,
      imageUrl: imageUrl,
      creatorName: creatorName,
      creatorUsername: creatorUsername,
      previewStorageUrl: previewStorageUrl,
      tags: List<String>.from(tags),
      folderId: sourceFolder?.name ?? 'tutti',
      createdAt: savedDate,
      updatedAt: DateTime.now(),
    );
  }
}

// ============================================================================
// FOLDER (MockFolder è importato da models/folder.dart)
// ============================================================================

// lib/models/folder.dart
// Modello Folder per database con supporto parentId

class Folder {
  final String id;
  final String name;
  final String color;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isDefault;
  final String? parentId; // NUOVO: riferimento al parent
  final bool isShared; // 🆕 NUOVO: Indica se la cartella è condivisa

  Folder({
    required this.id,
    required this.name,
    required this.color,
    required this.createdAt,
    this.updatedAt,
    this.isDefault = false,
    this.parentId,
    this.isShared = false,
  });

  bool get isValid => id.isNotEmpty && name.isNotEmpty;

  factory Folder.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Folder(
      id: doc.id,
      name: data['name'] ?? 'Unnamed',
      color: data['color'] ?? '#BB86FC',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      isDefault: data['isDefault'] ?? false,
      parentId: data['parentId'],
      isShared: data['isShared'] ?? false,
    );
  }

  factory Folder.fromMap(Map<String, dynamic> map, String id) {
    return Folder(
      id: id,
      name: map['name'] ?? 'Unnamed',
      color: map['color'] ?? '#BB86FC',
      createdAt: map['createdAt'] is Timestamp
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: map['updatedAt'] is Timestamp
          ? (map['updatedAt'] as Timestamp).toDate()
          : null,
      isDefault: map['isDefault'] ?? false,
      parentId: map['parentId'],
      isShared: map['isShared'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'color': color,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null
          ? Timestamp.fromDate(updatedAt!)
          : FieldValue.serverTimestamp(),
      'isDefault': isDefault,
      'parentId': parentId,
      'isShared': isShared,
    };
  }

  Folder copyWith({
    String? id,
    String? name,
    String? color,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDefault,
    String? parentId,
    bool? isShared,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDefault: isDefault ?? this.isDefault,
      parentId: parentId ?? this.parentId,
      isShared: isShared ?? this.isShared,
    );
  }

  @override
  String toString() {
    return 'Folder(id: $id, name: $name, isDefault: $isDefault, parentId: $parentId)';
  }
}

// ============================================================================
// URL METADATA
// ============================================================================

class UrlMetadata {
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? previewStorageUrl;
  final String? creatorName;
  final String? creatorUsername;
  final String? siteName;
  final String? favicon;
  final List<String> extractedHashtags;
  /// true se i metadati provengono da global_posts (già importato da altro utente).
  final bool fromGlobalCache;

  UrlMetadata({
    this.title,
    this.description,
    this.imageUrl,
    this.previewStorageUrl,
    this.creatorName,
    this.creatorUsername,
    this.siteName,
    this.favicon,
    this.extractedHashtags = const [],
    this.fromGlobalCache = false,
  });

  factory UrlMetadata.fromJson(Map<String, dynamic> json) {
    return UrlMetadata(
      title: json['title'],
      description: json['description'],
      imageUrl: json['imageUrl'],
      previewStorageUrl: json['previewStorageUrl'],
      creatorName: json['creatorName'],
      creatorUsername: json['creatorUsername'],
      siteName: json['siteName'],
      favicon: json['favicon'],
      extractedHashtags: json['extractedHashtags'] != null
          ? List<String>.from(json['extractedHashtags'])
          : [],
      fromGlobalCache: json['fromGlobalCache'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'previewStorageUrl': previewStorageUrl,
      'creatorName': creatorName,
      'creatorUsername': creatorUsername,
      'siteName': siteName,
      'favicon': favicon,
      'extractedHashtags': extractedHashtags,
      'fromGlobalCache': fromGlobalCache,
    };
  }

  /// Anteprima da mostrare in UI (preferisce storage condiviso).
  String? get displayImageUrl {
    final stable = previewStorageUrl?.trim();
    if (stable != null && stable.isNotEmpty) return stable;
    final original = imageUrl?.trim();
    if (original != null && original.isNotEmpty) return original;
    return null;
  }

  bool get hasValidData =>
      title?.isNotEmpty == true ||
      description?.isNotEmpty == true ||
      imageUrl?.isNotEmpty == true ||
      previewStorageUrl?.isNotEmpty == true;

  bool get hasExtractedHashtags => extractedHashtags.isNotEmpty;

  String getDisplayTitle({String fallback = 'Contenuto senza titolo'}) =>
      title?.isNotEmpty == true ? title! : fallback;

  String getDisplayDescription(
          {String fallback = 'Nessuna descrizione disponibile'}) =>
      description?.isNotEmpty == true ? description! : fallback;

  UrlMetadata copyWith({
    String? title,
    String? description,
    String? imageUrl,
    String? creatorName,
    String? creatorUsername,
    String? siteName,
    String? favicon,
    List<String>? extractedHashtags,
  }) {
    return UrlMetadata(
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      creatorName: creatorName ?? this.creatorName,
      creatorUsername: creatorUsername ?? this.creatorUsername,
      siteName: siteName ?? this.siteName,
      favicon: favicon ?? this.favicon,
      extractedHashtags: extractedHashtags ?? this.extractedHashtags,
    );
  }
}

// ============================================================================
// REMINDER
// ============================================================================

class Reminder {
  final String id;

  /// 'post' oppure 'folder'
  final String targetType;
  final String postId;
  final String postTitle;
  final String postUrl;
  final String? folderId;
  final String? folderName;
  final int reminderDay;
  final int reminderMonth;
  final int reminderHour;
  final int reminderMinute;
  final bool isYearly;
  final int notificationId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastTriggeredAt;

  Reminder({
    required this.id,
    this.targetType = 'post',
    required this.postId,
    required this.postTitle,
    required this.postUrl,
    this.folderId,
    this.folderName,
    required this.reminderDay,
    required this.reminderMonth,
    this.reminderHour = 9,
    this.reminderMinute = 0,
    required this.isYearly,
    required this.notificationId,
    this.isActive = true,
    required this.createdAt,
    this.lastTriggeredAt,
  });

  bool get isFolderReminder => targetType == 'folder';

  /// Titolo da mostrare nelle UI (funziona sia per post che per cartelle)
  String get displayTitle {
    if (isFolderReminder) return folderName ?? folderId ?? '';
    return postTitle.isNotEmpty ? postTitle : postUrl;
  }

  factory Reminder.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Reminder(
      id: doc.id,
      targetType: data['targetType'] ?? 'post',
      postId: data['postId'] ?? '',
      postTitle: data['postTitle'] ?? '',
      postUrl: data['postUrl'] ?? '',
      folderId: data['folderId'],
      folderName: data['folderName'],
      reminderDay: data['reminderDay'] ?? 1,
      reminderMonth: data['reminderMonth'] ?? 1,
      reminderHour: data['reminderHour'] ?? 9,
      reminderMinute: data['reminderMinute'] ?? 0,
      isYearly: data['isYearly'] ?? true,
      notificationId: data['notificationId'] ?? 0,
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastTriggeredAt: (data['lastTriggeredAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'targetType': targetType,
      'postId': postId,
      'postTitle': postTitle,
      'postUrl': postUrl,
      'folderId': folderId,
      'folderName': folderName,
      'reminderDay': reminderDay,
      'reminderMonth': reminderMonth,
      'reminderHour': reminderHour,
      'reminderMinute': reminderMinute,
      'isYearly': isYearly,
      'notificationId': notificationId,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastTriggeredAt':
          lastTriggeredAt != null ? Timestamp.fromDate(lastTriggeredAt!) : null,
    };
  }

  Reminder copyWith({bool? isActive, DateTime? lastTriggeredAt}) {
    return Reminder(
      id: id,
      targetType: targetType,
      postId: postId,
      postTitle: postTitle,
      postUrl: postUrl,
      folderId: folderId,
      folderName: folderName,
      reminderDay: reminderDay,
      reminderMonth: reminderMonth,
      reminderHour: reminderHour,
      reminderMinute: reminderMinute,
      isYearly: isYearly,
      notificationId: notificationId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      lastTriggeredAt: lastTriggeredAt ?? this.lastTriggeredAt,
    );
  }

  String get monthName {
    const months = [
      'gennaio',
      'febbraio',
      'marzo',
      'aprile',
      'maggio',
      'giugno',
      'luglio',
      'agosto',
      'settembre',
      'ottobre',
      'novembre',
      'dicembre',
    ];
    return months[reminderMonth - 1];
  }

  String get displayTime =>
      '${reminderHour.toString().padLeft(2, '0')}:${reminderMinute.toString().padLeft(2, '0')}';

  bool get isPast {
    if (isYearly) return false;
    final now = DateTime.now();
    final reminderDate = DateTime(
        now.year, reminderMonth, reminderDay, reminderHour, reminderMinute);
    return reminderDate.isBefore(now);
  }

  String get displayDate => isYearly
      ? '$reminderDay $monthName alle $displayTime (ripetuto ogni anno)'
      : '$reminderDay $monthName alle $displayTime (una sola volta)';
}

// ============================================================================
// FIRESTORE EXCEPTION
// ============================================================================

class FirestoreConversionException implements Exception {
  final String message;
  final String? fieldName;
  final dynamic originalError;

  FirestoreConversionException(this.message,
      {this.fieldName, this.originalError});

  @override
  String toString() =>
      'FirestoreConversionException: $message${fieldName != null ? ' (field: $fieldName)' : ''}';
}

// ============================================================================
// FIRESTORE EXTENSIONS
// ============================================================================

extension SavedPostFirestore on SavedPost {
  static SavedPost fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      if (data == null) {
        throw FirestoreConversionException('Documento post vuoto',
            fieldName: 'doc.data');
      }

      final url = data['url'] as String?;
      if (url == null || url.isEmpty) {
        throw FirestoreConversionException('URL post mancante o vuoto',
            fieldName: 'url');
      }

      final title = data['title'] as String?;
      if (title == null || title.isEmpty) {
        throw FirestoreConversionException('Titolo post mancante o vuoto',
            fieldName: 'title');
      }

      final folderId = data['folderId'] as String?;
      if (folderId == null || folderId.isEmpty) {
        throw FirestoreConversionException('FolderId post mancante o vuoto',
            fieldName: 'folderId');
      }

      List<String> tags = [];
      try {
        final tagsData = data['tags'];
        if (tagsData != null) {
          tags = List<String>.from(tagsData);
        }
      } catch (e) {
        print('WARNING: Errore conversione tags per post ${doc.id}: $e');
        tags = [];
      }

      DateTime createdAt;
      try {
        final createdAtData = data['createdAt'];
        if (createdAtData is Timestamp) {
          createdAt = createdAtData.toDate();
        } else if (createdAtData is String) {
          createdAt = DateTime.parse(createdAtData);
        } else {
          createdAt = DateTime.now();
        }
      } catch (e) {
        print('WARNING: Errore conversione createdAt per post ${doc.id}: $e');
        createdAt = DateTime.now();
      }

      DateTime? updatedAt;
      try {
        final updatedAtData = data['updatedAt'];
        if (updatedAtData is Timestamp) {
          updatedAt = updatedAtData.toDate();
        } else if (updatedAtData is String) {
          updatedAt = DateTime.parse(updatedAtData);
        }
      } catch (e) {
        print('WARNING: Errore conversione updatedAt per post ${doc.id}: $e');
        updatedAt = null;
      }

      final post = SavedPost(
        id: doc.id,
        url: url,
        title: title,
        description: data['description'] as String? ?? '',
        imageUrl: data['imageUrl'] as String?,
        creatorName: data['creatorName'] as String?,
        creatorUsername: data['creatorUsername'] as String?,
        previewStorageUrl: data['previewStorageUrl'] as String?,
        tags: tags,
        folderId: folderId,
        createdAt: createdAt,
        updatedAt: updatedAt,
        isShared: data['isShared'] as bool? ?? false,
      );

      if (!post.isValid) {
        throw FirestoreConversionException('Post non valido dopo conversione',
            fieldName: 'validation');
      }

      return post;
    } catch (e) {
      if (e is FirestoreConversionException) {
        rethrow;
      }
      throw FirestoreConversionException(
          'Errore generale conversione post da Firestore: $e',
          originalError: e);
    }
  }

  Map<String, dynamic> toFirestore() {
    if (!isValid) {
      throw FirestoreConversionException(
          'Post non valido per conversione Firestore');
    }

    try {
      return {
        'url': url.trim(),
        'title': title.trim(),
        'description': description.trim(),
        'imageUrl': imageUrl?.trim(),
        'creatorName': creatorName?.trim(),
        'creatorUsername': creatorUsername?.trim(),
        'previewStorageUrl': previewStorageUrl?.trim(),
        'tags': tags
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList(),
        'folderId': folderId,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
        'isShared': isShared,
      };
    } catch (e) {
      throw FirestoreConversionException(
          'Errore conversione post a Firestore: $e',
          originalError: e);
    }
  }
}

extension FolderFirestore on Folder {
  static Folder fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      if (data == null) {
        throw FirestoreConversionException('Documento folder vuoto',
            fieldName: 'doc.data');
      }

      final name = data['name'] as String?;
      if (name == null || name.isEmpty) {
        throw FirestoreConversionException('Nome folder mancante o vuoto',
            fieldName: 'name');
      }

      final color = data['color'] as String? ?? '#BB86FC';
      final isDefault = data['isDefault'] as bool? ?? false;

      DateTime createdAt;
      try {
        final createdAtData = data['createdAt'];
        if (createdAtData is Timestamp) {
          createdAt = createdAtData.toDate();
        } else if (createdAtData is String) {
          createdAt = DateTime.parse(createdAtData);
        } else {
          createdAt = DateTime.now();
        }
      } catch (e) {
        print('WARNING: Errore conversione createdAt per folder ${doc.id}: $e');
        createdAt = DateTime.now();
      }

      DateTime? updatedAt;
      try {
        final updatedAtData = data['updatedAt'];
        if (updatedAtData is Timestamp) {
          updatedAt = updatedAtData.toDate();
        } else if (updatedAtData is String) {
          updatedAt = DateTime.parse(updatedAtData);
        }
      } catch (e) {
        print('WARNING: Errore conversione updatedAt per folder ${doc.id}: $e');
        updatedAt = null;
      }

      final folder = Folder(
        id: doc.id,
        name: name,
        color: color,
        createdAt: createdAt,
        updatedAt: updatedAt,
        isDefault: isDefault,
      );

      if (!folder.isValid) {
        throw FirestoreConversionException('Folder non valido dopo conversione',
            fieldName: 'validation');
      }

      return folder;
    } catch (e) {
      if (e is FirestoreConversionException) {
        rethrow;
      }
      throw FirestoreConversionException(
          'Errore generale conversione folder da Firestore: $e',
          originalError: e);
    }
  }

  Map<String, dynamic> toFirestore() {
    if (!isValid) {
      throw FirestoreConversionException(
          'Folder non valido per conversione Firestore');
    }

    try {
      return {
        'name': name.trim(),
        'color': color,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
        'isDefault': isDefault,
      };
    } catch (e) {
      throw FirestoreConversionException(
          'Errore conversione folder a Firestore: $e',
          originalError: e);
    }
  }
}

extension UrlMetadataFirestore on UrlMetadata {
  Map<String, dynamic> toFirestore() {
    return {
      'title': title?.trim(),
      'description': description?.trim(),
      'imageUrl': imageUrl?.trim(),
      'previewStorageUrl': previewStorageUrl?.trim(),
      'creatorName': creatorName?.trim(),
      'creatorUsername': creatorUsername?.trim(),
      'siteName': siteName?.trim(),
      'favicon': favicon?.trim(),
      'extractedHashtags': extractedHashtags.map((tag) => tag.trim()).toList(),
      'createdAt': Timestamp.now(),
    };
  }

  static UrlMetadata fromFirestore(Map<String, dynamic> data) {
    return UrlMetadata(
      title: data['title'] as String?,
      description: data['description'] as String?,
      imageUrl: data['imageUrl'] as String?,
      previewStorageUrl: data['previewStorageUrl'] as String?,
      creatorName: data['creatorName'] as String?,
      creatorUsername: data['creatorUsername'] as String?,
      siteName: data['siteName'] as String?,
      favicon: data['favicon'] as String?,
      extractedHashtags: data['extractedHashtags'] != null
          ? List<String>.from(data['extractedHashtags'])
          : [],
    );
  }
}
