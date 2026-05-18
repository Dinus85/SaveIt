// File: lib/services/folder_service_search.dart
// Funzionalità di ricerca e filtri

import 'package:flutter/material.dart';
import '../advanced_analytics_models.dart';
import '../models.dart';
import '../models/folder.dart';


import 'folder_service_models.dart';
import 'folder_service_base.dart';

/// Mixin per funzionalità di ricerca
mixin FolderServiceSearch on FolderServiceBase {
  
  // ============================================================================
  // RICERCA UNIFICATA
  // ============================================================================
  
  List<SearchResult> searchUnified(String query, {bool trackSearch = true}) {
    if (query.trim().isEmpty) return [];
    
    startActionTiming('unified_search');
    
    List<String> searchTerms = extractSearchTerms(query);
    if (searchTerms.isEmpty) return [];
    
    List<SearchResult> results = [];
    
    // Cerca nelle cartelle
    results.addAll(searchInFolders(searchTerms));
    
    // Cerca nei post
    results.addAll(searchInPosts(searchTerms));
    
    // Ordina per rilevanza
    results.sort((a, b) {
      if (a.type == 'post' && b.type == 'folder') return -1;
      if (a.type == 'folder' && b.type == 'post') return 1;
      
      if (a.type == 'post' && b.type == 'post') {
        return b.post!.savedDate.compareTo(a.post!.savedDate);
      }
      
      return a.title.compareTo(b.title);
    });
    
    // Track ricerca
    if (trackSearch && query.trim().length >= 2) {
      final duration = endActionTiming('unified_search');
      
      analytics.trackSearchPerformed(query, results.length);
      
      advancedAnalytics.trackAdvancedEvent(
        AdvancedEventType.actionPerformed,
        properties: {
          'action': 'unified_search',
          'query': query,
          'search_terms': searchTerms,
          'results_count': results.length,
          'folder_results': results.where((r) => r.type == 'folder').length,
          'post_results': results.where((r) => r.type == 'post').length,
          'search_time_ms': duration?.inMilliseconds,
        },
        actionDuration: duration,
      );
    }
    
    return results;
  }
  
  // ============================================================================
  // ESTRAZIONE TERMINI DI RICERCA
  // ============================================================================
  
  List<String> extractSearchTerms(String query) {
    String cleanQuery = query
        .replaceAll(RegExp(r'^#'), '')
        .replaceAll(RegExp(r'[,;]+'), ' ')
        .trim();
    
    List<String> terms = cleanQuery
        .split(RegExp(r'\s+'))
        .where((term) => term.trim().isNotEmpty)
        .map((term) => term.toLowerCase().trim())
        .toList();
    
    return terms;
  }
  
  // ============================================================================
  // RICERCA NELLE CARTELLE
  // ============================================================================
  
  List<SearchResult> searchInFolders(List<String> searchTerms) {
    List<SearchResult> folderResults = [];
    
    void searchInFolderRecursive(MockFolder folder, [String path = '']) {
      if (folder.isSpecial) return;
      
      final currentPath = path.isEmpty ? folder.name : '$path › ${folder.name}';
      final folderNameLower = folder.name.toLowerCase();
      
      List<String> matchedTerms = [];
      bool allTermsMatch = true;
      
      for (String term in searchTerms) {
        if (folderNameLower.contains(term)) {
          matchedTerms.add(term);
        } else {
          allTermsMatch = false;
          break;
        }
      }
      
      if (allTermsMatch && matchedTerms.isNotEmpty) {
        folderResults.add(SearchResult(
          type: 'folder',
          title: currentPath,
          subtitle: folder.count,
          color: folder.color,
          folder: folder,
          matchedTerms: matchedTerms,
        ));
      }
      
      for (var child in folder.children) {
        searchInFolderRecursive(child, currentPath);
      }
    }
    
    for (var folder in folders) {
      searchInFolderRecursive(folder);
    }
    
    return folderResults;
  }
  
  // ============================================================================
  // RICERCA NEI POST
  // ============================================================================
  
  List<SearchResult> searchInPosts(List<String> searchTerms) {
    List<SearchResult> postResults = [];
    
    for (MockPost post in allPosts) {
      List<String> matchedTerms = [];
      bool allTermsMatch = true;
      
      for (String term in searchTerms) {
        bool termFound = false;
        
        // Cerca nei tag
        for (String tag in post.tags) {
          if (tag.toLowerCase().contains(term)) {
            if (!matchedTerms.contains(term)) {
              matchedTerms.add(term);
            }
            termFound = true;
            break;
          }
        }
        
        // Cerca nel titolo e descrizione
        if (!termFound) {
          if (post.title.toLowerCase().contains(term) || 
              post.description.toLowerCase().contains(term)) {
            if (!matchedTerms.contains(term)) {
              matchedTerms.add(term);
            }
            termFound = true;
          }
        }
        
        if (!termFound) {
          allTermsMatch = false;
          break;
        }
      }
      
      if (allTermsMatch && matchedTerms.isNotEmpty) {
        String folderPath = 'Tutti';
        if (post.sourceFolder != null) {
          folderPath = buildFolderPath(post.sourceFolder!);
        }
        
        postResults.add(SearchResult(
          type: 'post',
          title: post.title,
          subtitle: '$folderPath • ${formatDate(post.savedDate)}',
          color: null,
          post: post,
          matchedTerms: matchedTerms,
        ));
      }
    }
    
    return postResults;
  }
  
  // ============================================================================
  // UTILITY METHODS
  // ============================================================================
  
  String buildFolderPath(MockFolder folder) {
    List<String> path = [];
    MockFolder? current = folder;
    
    while (current != null) {
      if (!current.isSpecial) {
        path.insert(0, current.name);
      }
      current = current.parent;
    }
    
    return path.isEmpty ? 'Home' : 'Home › ${path.join(' › ')}';
  }
  
  String formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return 'Oggi';
    } else if (difference.inDays == 1) {
      return 'Ieri';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} giorni fa';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
  
  // ============================================================================
  // RICERCA LEGACY (per compatibilità)
  // ============================================================================
  
  List<MockFolder> searchFolders(String query) {
    final results = searchUnified(query);
    return results
        .where((r) => r.type == 'folder' && r.folder != null)
        .map((r) => MockFolder(
          name: r.title,
          count: r.subtitle,
          color: r.color ?? Colors.grey,
          level: r.folder!.level,
          originalFolder: r.folder,
        ))
        .toList();
  }
  
  List<MockPost> searchPosts(String query) {
    final results = searchUnified(query);
    return results
        .where((r) => r.type == 'post' && r.post != null)
        .map((r) => r.post!)
        .toList();
  }
  
  // ============================================================================
  // NAVIGAZIONE E FILTRI
  // ============================================================================
  
  List<FlatFolder> getAllFoldersFlat() {
    List<FlatFolder> flatFolders = [];
    
    void flattenFolder(MockFolder folder, String parentPath, int level) {
      if (folder.isSpecial) return;
      
      final currentPath = parentPath.isEmpty ? folder.name : '$parentPath › ${folder.name}';
      
      flatFolders.add(FlatFolder(
        folder: folder,
        fullPath: currentPath,
        level: level,
        hasChildren: folder.children.isNotEmpty,
      ));
      
      for (var child in folder.children) {
        flattenFolder(child, currentPath, level + 1);
      }
    }
    
    for (var folder in folders) {
      if (!folder.isSpecial) {
        flattenFolder(folder, '', 0);
      }
    }
    
    return flatFolders;
  }
  
  List<MockFolder> getRootFolders() {
    return folders.where((folder) => !folder.isSpecial && folder.level == 0).toList();
  }
  
  MockFolder? findFolderByPath(String path) {
    if (path.isEmpty) return null;
    
    String cleanPath = path;
    if (cleanPath.startsWith('Home › ')) {
      cleanPath = cleanPath.substring(7);
    }
    
    final pathParts = cleanPath.split(' › ');
    
    MockFolder? currentFolder;
    
    for (var folder in folders) {
      if (folder.name == pathParts.first && !folder.isSpecial) {
        currentFolder = folder;
        break;
      }
    }
    
    if (currentFolder == null) return null;
    
    for (int i = 1; i < pathParts.length; i++) {
      final targetName = pathParts[i];
      
      MockFolder? found;
      for (var child in currentFolder!.children) {
        if (child.name == targetName) {
          found = child;
          break;
        }
      }
      
      if (found == null) return null;
      currentFolder = found;
    }
    
    return currentFolder;
  }
  
  // ============================================================================
  // GESTIONE IMMAGINI
  // ============================================================================
  
  /// Ritorna gli ultimi post (max N) che hanno un'anteprima immagine disponibile.
  /// Utile per UI che vuole gestire fallback (cache locale -> network).
  List<MockPost> getLastPostsWithImagesForFolder(MockFolder folder, {int maxPosts = 4}) {
    final List<MockPost> postsWithImages = <MockPost>[];

    if (folder.isSpecial) {
      postsWithImages.addAll(
        allPosts.where((post) => post.imageUrl != null && post.imageUrl!.isNotEmpty),
      );
    } else {
      void collectPostsRecursively(MockFolder currentFolder) {
        final directPosts = allPosts
            .where((post) {
              // 1) confronto referenziale
              if (post.sourceFolder == currentFolder) return true;

              // 2) confronto ID (per gestire istanze rigenerate dopo sync)
              if (post.sourceFolder?.id != null && currentFolder.id != null) {
                return post.sourceFolder!.id == currentFolder.id;
              }

              return false;
            })
            .where((post) => post.imageUrl != null && post.imageUrl!.isNotEmpty)
            .toList();

        postsWithImages.addAll(directPosts);

        for (var child in currentFolder.children) {
          collectPostsRecursively(child);
        }
      }

      collectPostsRecursively(folder);
    }

    postsWithImages.sort((a, b) => b.savedDate.compareTo(a.savedDate));
    return postsWithImages.take(maxPosts).toList();
  }

  List<String> getLastPostImagesForFolder(MockFolder folder, {int maxImages = 4}) {
    return getLastPostsWithImagesForFolder(folder, maxPosts: maxImages)
        .map((p) => p.imageUrl!)
        .toList();
  }
  
  bool folderHasPostsWithImages(MockFolder folder) {
    final images = getLastPostImagesForFolder(folder, maxImages: 1);
    return images.isNotEmpty;
  }
  
  Map<String, int> getFolderImageStats(MockFolder folder) {
    try {
      final allImages = getLastPostImagesForFolder(folder, maxImages: 100);
      final recentImages = getLastPostImagesForFolder(folder, maxImages: 4);
      
      return {
        'totalImages': allImages.length,
        'recentImages': recentImages.length,
        'hasImages': allImages.isNotEmpty ? 1 : 0,
      };
    } catch (e) {
      return {
        'totalImages': 0,
        'recentImages': 0,
        'hasImages': 0,
      };
    }
  }
  
  int getTotalPostsWithImages() {
    return allPosts
        .where((post) => post.imageUrl != null && post.imageUrl!.isNotEmpty)
        .length;
  }
}