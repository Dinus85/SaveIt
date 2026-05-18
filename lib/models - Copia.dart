// lib/models.dart
// Modelli con estensioni Firestore - Fase 4 completata
// 🔥 SISTEMATO: Rimosse duplicazioni MockFolder e fix import

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
// 🔧 AGGIUNTO: Import per MockFolder da folder.dart per evitare duplicazioni
import '../models/folder.dart' show MockFolder;

class SavedPost {
  final String id;
  final String url;
  final String title;
  final String description;
  final String? imageUrl; // AGGIUNTO: Campo per immagine Open Graph
  final List<String> tags;
  final String folderId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  SavedPost({
    required this.id,
    required this.url,
    required this.title,
    required this.description,
    this.imageUrl, // AGGIUNTO: Parametro opzionale
    required this.tags,
    required this.folderId,
    required this.createdAt,
    this.updatedAt,
  });

  // Convert to JSON for storage (mantenuto per compatibilità)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'title': title,
      'description': description,
      'imageUrl': imageUrl, // AGGIUNTO: Includi nel JSON
      'tags': tags,
      'folderId': folderId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  // Create from JSON (mantenuto per compatibilità)
  factory SavedPost.fromJson(Map<String, dynamic> json) {
    return SavedPost(
      id: json['id'] ?? '',
      url: json['url'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      imageUrl: json['imageUrl'], // AGGIUNTO: Leggi dal JSON
      tags: List<String>.from(json['tags'] ?? []),
      folderId: json['folderId'] ?? '',
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null 
          ? DateTime.parse(json['updatedAt']) 
          : null,
    );
  }

  // Create a copy with updated fields
  SavedPost copyWith({
    String? id,
    String? url,
    String? title,
    String? description,
    String? imageUrl, // AGGIUNTO: Parametro per copia
    List<String>? tags,
    String? folderId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SavedPost(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl, // AGGIUNTO: Usa nuovo valore o mantieni esistente
      tags: tags ?? this.tags,
      folderId: folderId ?? this.folderId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // 🆕 NUOVO: Metodo per convertire SavedPost a MockPost per aggiornamento ottimistico
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
    );
  }

  // Validation methods
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
  String get displayDescription => description.isNotEmpty ? description : 'Nessuna descrizione disponibile';
}

// 🆕 MANTENUTO: Classe MockPost (controllare se duplicata in folder_service.dart)
class MockPost {
  final String id;
  final String title;
  final String url;
  final String description;
  final DateTime savedDate;
  final MockFolder? sourceFolder;
  List<String> tags;
  final String? imageUrl;

  MockPost({
    required this.id,
    required this.title,
    required this.url,
    required this.description,
    required this.savedDate,
    this.sourceFolder,
    List<String>? tags,
    this.imageUrl,
  }) : tags = tags ?? [];

  // 🆕 NUOVO: Metodo per convertire MockPost a SavedPost quando necessario
  SavedPost toSavedPost() {
    return SavedPost(
      id: id,
      url: url,
      title: title,
      description: description,
      imageUrl: imageUrl,
      tags: List<String>.from(tags),
      folderId: sourceFolder?.name ?? 'tutti', // Fallback se sourceFolder è null
      createdAt: savedDate,
      updatedAt: DateTime.now(),
    );
  }
}

// 🔧 RIMOSSA: Definizione duplicata di MockFolder (ora importata da ../models/folder.dart)

class Folder {
  final String id;
  final String name;
  final String color; // Hex color string
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isDefault; // Per la cartella "Tutti"

  Folder({
    required this.id,
    required this.name,
    required this.color,
    required this.createdAt,
    this.updatedAt,
    this.isDefault = false,
  });

  // Convert to JSON for storage (mantenuto per compatibilità)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'color': color,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'isDefault': isDefault,
    };
  }

  // Create from JSON (mantenuto per compatibilità)
  factory Folder.fromJson(Map<String, dynamic> json) {
    return Folder(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      color: json['color'] ?? '#BB86FC',
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null 
          ? DateTime.parse(json['updatedAt']) 
          : null,
      isDefault: json['isDefault'] ?? false,
    );
  }

  // Create a copy with updated fields
  Folder copyWith({
    String? id,
    String? name,
    String? color,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDefault,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  // 🆕 NUOVO: Metodo per convertire Folder a MockFolder per aggiornamento ottimistico
  MockFolder toMockFolder({String? displayCount}) {
    return MockFolder(
      name: name,
      count: displayCount ?? 'Vuota',
      color: _hexToColor(color),
      level: 0, // Le cartelle dal DB sono sempre root level inizialmente
      isSpecial: isDefault,
    );
  }

  // 🆕 NUOVO: Helper per conversione colore hex
  Color _hexToColor(String hexString) {
    try {
      final buffer = StringBuffer();
      if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (e) {
      print('DEBUG: Errore conversione colore $hexString: $e');
      return Colors.blue; // Fallback
    }
  }

  // Validation methods
  bool get isValid {
    return id.isNotEmpty &&
           name.isNotEmpty &&
           name.length <= 100 &&
           color.isNotEmpty &&
           _isValidHexColor(color);
  }

  bool _isValidHexColor(String color) {
    final hexColorRegex = RegExp(r'^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{8})$');
    return hexColorRegex.hasMatch(color);
  }

  String get displayName => name.isEmpty ? 'Cartella senza nome' : name;
}

// ENHANCED: Metadata estratti da un URL con supporto immagini migliorato
class UrlMetadata {
  final String? title;
  final String? description;
  final String? imageUrl; // Campo già presente, nessuna modifica necessaria
  final String? siteName;
  final String? favicon;
  final List<String> extractedHashtags; // 🆕 NUOVO: Hashtag estratti dai metadati

  UrlMetadata({
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    this.favicon,
    this.extractedHashtags = const [], // 🆕 NUOVO: Default lista vuota
  });

  factory UrlMetadata.fromJson(Map<String, dynamic> json) {
    return UrlMetadata(
      title: json['title'],
      description: json['description'],
      imageUrl: json['imageUrl'],
      siteName: json['siteName'],
      favicon: json['favicon'],
      extractedHashtags: json['extractedHashtags'] != null 
          ? List<String>.from(json['extractedHashtags'])
          : [], // 🆕 NUOVO: Deserializza hashtag
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'siteName': siteName,
      'favicon': favicon,
      'extractedHashtags': extractedHashtags, // 🆕 NUOVO: Serializza hashtag
    };
  }

  // AGGIUNTO: Metodo helper per verificare se ha contenuti validi
  bool get hasValidData => 
    title?.isNotEmpty == true || 
    description?.isNotEmpty == true || 
    imageUrl?.isNotEmpty == true;

  // 🆕 NUOVO: Verifica se ha hashtag estratti
  bool get hasExtractedHashtags => extractedHashtags.isNotEmpty;

  // AGGIUNTO: Metodo helper per ottenere titolo con fallback
  String getDisplayTitle({String fallback = 'Contenuto senza titolo'}) =>
    title?.isNotEmpty == true ? title! : fallback;

  // AGGIUNTO: Metodo helper per ottenere descrizione con fallback
  String getDisplayDescription({String fallback = 'Nessuna descrizione disponibile'}) =>
    description?.isNotEmpty == true ? description! : fallback;

  // AGGIUNTO: Metodo per copiare con modifiche
  UrlMetadata copyWith({
    String? title,
    String? description,
    String? imageUrl,
    String? siteName,
    String? favicon,
    List<String>? extractedHashtags, // 🆕 NUOVO: Parametro per hashtag
  }) {
    return UrlMetadata(
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      siteName: siteName ?? this.siteName,
      favicon: favicon ?? this.favicon,
      extractedHashtags: extractedHashtags ?? this.extractedHashtags, // 🆕 NUOVO
    );
  }
}

// ============================================================================
// ESTENSIONI FIRESTORE - SPOSTATE DA firebase_data_service.dart
// ============================================================================

/// Exception personalizzata per errori di conversione Firestore
class FirestoreConversionException implements Exception {
  final String message;
  final String? fieldName;
  final dynamic originalError;
  
  FirestoreConversionException(this.message, {this.fieldName, this.originalError});
  
  @override
  String toString() => 'FirestoreConversionException: $message${fieldName != null ? ' (field: $fieldName)' : ''}';
}

/// Estensioni Firestore per SavedPost
extension SavedPostFirestore on SavedPost {
  /// Crea SavedPost da DocumentSnapshot Firestore con validazione migliorata
  static SavedPost fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      if (data == null) {
        throw FirestoreConversionException('Documento post vuoto', fieldName: 'doc.data');
      }
      
      // Validazione campi obbligatori
      final url = data['url'] as String?;
      if (url == null || url.isEmpty) {
        throw FirestoreConversionException('URL post mancante o vuoto', fieldName: 'url');
      }
      
      final title = data['title'] as String?;
      if (title == null || title.isEmpty) {
        throw FirestoreConversionException('Titolo post mancante o vuoto', fieldName: 'title');
      }
      
      final folderId = data['folderId'] as String?;
      if (folderId == null || folderId.isEmpty) {
        throw FirestoreConversionException('FolderId post mancante o vuoto', fieldName: 'folderId');
      }
      
      // Conversione sicura dei campi
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
        tags: tags,
        folderId: folderId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
      
      // Validazione finale
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
        originalError: e
      );
    }
  }

  /// Converte SavedPost a Map per Firestore con validazione
  Map<String, dynamic> toFirestore() {
    // Validazione pre-conversione
    if (!isValid) {
      throw FirestoreConversionException('Post non valido per conversione Firestore');
    }
    
    try {
      return {
        'url': url.trim(),
        'title': title.trim(),
        'description': description.trim(),
        'imageUrl': imageUrl?.trim(),
        'tags': tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toList(),
        'folderId': folderId,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      };
    } catch (e) {
      throw FirestoreConversionException(
        'Errore conversione post a Firestore: $e',
        originalError: e
      );
    }
  }
}

/// Estensioni Firestore per Folder
extension FolderFirestore on Folder {
  /// Crea Folder da DocumentSnapshot Firestore con validazione migliorata
  static Folder fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      if (data == null) {
        throw FirestoreConversionException('Documento folder vuoto', fieldName: 'doc.data');
      }
      
      // Validazione campi obbligatori
      final name = data['name'] as String?;
      if (name == null || name.isEmpty) {
        throw FirestoreConversionException('Nome folder mancante o vuoto', fieldName: 'name');
      }
      
      // Conversione sicura dei campi
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
      
      // Validazione finale
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
        originalError: e
      );
    }
  }

  /// Converte Folder a Map per Firestore con validazione
  Map<String, dynamic> toFirestore() {
    // Validazione pre-conversione
    if (!isValid) {
      throw FirestoreConversionException('Folder non valido per conversione Firestore');
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
        originalError: e
      );
    }
  }
}

/// Estensioni Firestore per UrlMetadata (per future espansioni)
extension UrlMetadataFirestore on UrlMetadata {
  /// Converte UrlMetadata a Map per Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'title': title?.trim(),
      'description': description?.trim(),
      'imageUrl': imageUrl?.trim(),
      'siteName': siteName?.trim(),
      'favicon': favicon?.trim(),
      'extractedHashtags': extractedHashtags.map((tag) => tag.trim()).toList(),
      'createdAt': Timestamp.now(),
    };
  }

  /// Crea UrlMetadata da Map Firestore
  static UrlMetadata fromFirestore(Map<String, dynamic> data) {
    return UrlMetadata(
      title: data['title'] as String?,
      description: data['description'] as String?,
      imageUrl: data['imageUrl'] as String?,
      siteName: data['siteName'] as String?,
      favicon: data['favicon'] as String?,
      extractedHashtags: data['extractedHashtags'] != null 
          ? List<String>.from(data['extractedHashtags']) 
          : [],
    );
  }
}