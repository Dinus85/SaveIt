// File: lib/services/folder_service_analytics.dart
// Analytics avanzati e tracking comportamentale

import '../advanced_analytics_models.dart';
import '../models.dart';
import '../data_service.dart';
import '../models/folder.dart';


import 'folder_service_models.dart';
import 'folder_service_base.dart';

/// Mixin per funzionalità analytics
mixin FolderServiceAnalytics on FolderServiceBase {
  
  // ============================================================================
  // TRACKING EVENTI
  // ============================================================================
  
  void trackFolderOpened(MockFolder folder) {
    analytics.trackFolderOpened(folder.name);
    
    advancedAnalytics.trackAdvancedEvent(
      AdvancedEventType.actionPerformed,
      properties: {
        'action': 'folder_opened',
        'folder_name': folder.name,
        'folder_level': folder.level,
        'is_special': folder.isSpecial,
        'user_id': currentUserId,
      },
    );
  }
  
  void trackPostViewed(MockPost post) {
    startActionTiming('view_post');
    
    final socialNetwork = extractSocialNetwork(post.url);
    analytics.trackPostViewed(
      post.title,
      post.sourceFolder?.name ?? 'Tutti',
      socialNetwork: socialNetwork,
    );
    
    final folderPath = post.sourceFolder != null 
        ? buildHierarchicalPathForTracking(post.sourceFolder!) 
        : 'Tutti';
    
    final duration = endActionTiming('view_post');
    
    advancedAnalytics.trackAdvancedEvent(
      AdvancedEventType.contentRevisited,
      properties: {
        'action': 'post_viewed',
        'post_id': post.id,
        'post_title': post.title,
        'post_url': post.url,
        'folder_path': folderPath,
        'social_network': socialNetwork,
        'has_image': post.imageUrl != null,
        'tag_count': post.tags.length,
        'saved_days_ago': DateTime.now().difference(post.savedDate).inDays,
        'view_time_ms': duration?.inMilliseconds,
      },
      actionDuration: duration,
    );
    
    advancedAnalytics.trackContentInteraction(
      post.id,
      post.title,
      post.url,
      folderPath: folderPath,
      tags: post.tags,
      socialNetwork: socialNetwork,
      isOpening: true,
      viewDuration: duration,
    );
  }
  
  // ============================================================================
  // METRICHE ORGANIZZATIVE
  // ============================================================================
  
  Future<OrganizationalMetrics> calculateOrganizationalMetrics() async {
    try {
      final allDepths = <int>[];
      final flatFolders = <MockFolder>[];
      final nestedFolders = <MockFolder>[];
      final emptyFolders = <MockFolder>[];
      final depthDistribution = <int, int>{};
      
      void analyzeFolder(MockFolder folder) {
        if (folder.isSpecial) return;
        
        final depth = folder.level;
        allDepths.add(depth);
        
        depthDistribution[depth] = (depthDistribution[depth] ?? 0) + 1;
        
        if (folder.children.isEmpty) {
          flatFolders.add(folder);
        } else {
          nestedFolders.add(folder);
        }
        
        if (folder.count == 'Vuota') {
          emptyFolders.add(folder);
        }
        
        for (var child in folder.children) {
          analyzeFolder(child);
        }
      }
      
      for (var folder in folders) {
        analyzeFolder(folder);
      }
      
      final totalFolders = folders.where((f) => !f.isSpecial).length;
      final avgFolderDepth = allDepths.isNotEmpty 
          ? allDepths.reduce((a, b) => a + b) / allDepths.length 
          : 0.0;
      final maxFolderDepth = allDepths.isNotEmpty 
          ? allDepths.reduce((a, b) => a > b ? a : b) 
          : 0;
      
      final foldersUtilizationRate = totalFolders > 0 
          ? (totalFolders - emptyFolders.length) / totalFolders 
          : 0.0;
      
      final underutilizedFolders = <String>[];
      final overutilizedFolders = <String>[];
      
      for (var folder in folders) {
        if (folder.isSpecial) continue;
        
        final postCount = allPosts.where((p) => p.sourceFolder == folder).length;
        
        if (postCount == 0 && DateTime.now().difference(DateTime.now()).inDays > 30) {
          underutilizedFolders.add(folder.name);
        } else if (postCount > 50) {
          overutilizedFolders.add(folder.name);
        }
      }
      
      double organizationalEfficiency = 0.0;
      if (totalFolders > 0) {
        final depthScore = avgFolderDepth <= 3 ? 1.0 : (3.0 / avgFolderDepth);
        final utilizationScore = foldersUtilizationRate;
        final balanceScore = nestedFolders.length > 0 
            ? (flatFolders.length / (flatFolders.length + nestedFolders.length)) 
            : 1.0;
        
        organizationalEfficiency = (depthScore + utilizationScore + balanceScore) / 3.0;
      }
      
      final metrics = OrganizationalMetrics(
        avgFolderDepth: avgFolderDepth,
        maxFolderDepth: maxFolderDepth,
        totalFolders: totalFolders,
        flatFolders: flatFolders.length,
        nestedFolders: nestedFolders.length,
        emptyFolders: emptyFolders.length,
        foldersUtilizationRate: foldersUtilizationRate,
        depthDistribution: depthDistribution,
        underutilizedFolders: underutilizedFolders,
        overutilizedFolders: overutilizedFolders,
        organizationalEfficiency: organizationalEfficiency.clamp(0.0, 1.0),
      );
      
      advancedAnalytics.trackAdvancedEvent(
        AdvancedEventType.organizationalEfficiencyChanged,
        properties: {
          'total_folders': totalFolders,
          'avg_depth': avgFolderDepth,
          'efficiency_score': organizationalEfficiency,
        },
      );
      
      return metrics;
      
    } catch (e) {
      print('ERRORE: Calcolo metriche fallito: $e');
      return OrganizationalMetrics(
        avgFolderDepth: 0.0,
        maxFolderDepth: 0,
        totalFolders: 0,
        flatFolders: 0,
        nestedFolders: 0,
        emptyFolders: 0,
        foldersUtilizationRate: 0.0,
        depthDistribution: {},
        underutilizedFolders: [],
        overutilizedFolders: [],
        organizationalEfficiency: 0.0,
      );
    }
  }
  
  // ============================================================================
  // PATTERN COMPORTAMENTALI
  // ============================================================================
  
  List<String> detectBehavioralPatterns() {
    final patterns = <String>[];
    
    try {
      final recentPosts = allPosts.where((p) => 
        DateTime.now().difference(p.savedDate).inDays <= 7
      ).toList();
      
      if (recentPosts.length > 10) {
        patterns.add('Salvataggio intensivo (${recentPosts.length} post questa settimana)');
      }
      
      final allTags = allPosts.expand((p) => p.tags).toList();
      final tagCounts = <String, int>{};
      for (var tag in allTags) {
        tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
      }
      
      final frequentTags = tagCounts.entries
          .where((e) => e.value >= 3)
          .map((e) => e.key)
          .toList();
      
      if (frequentTags.isNotEmpty) {
        patterns.add('Tag frequenti: ${frequentTags.take(3).join(", ")}');
      }
      
      final socialNetworks = allPosts
          .map((p) => extractSocialNetwork(p.url))
          .where((s) => s != null)
          .toList();
      
      final socialCounts = <String, int>{};
      for (var social in socialNetworks) {
        socialCounts[social!] = (socialCounts[social] ?? 0) + 1;
      }
      
      final topSocial = socialCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      
      if (topSocial.isNotEmpty && topSocial.first.value >= 3) {
        patterns.add('Fonte principale: ${topSocial.first.key}');
      }
      
    } catch (e) {
      print('ERRORE: Rilevamento pattern fallito: $e');
    }
    
    return patterns;
  }
  
  List<MockPost> detectNeverOpenedContent() {
    final neverOpened = <MockPost>[];
    
    try {
      final oldPosts = allPosts.where((post) => 
        DateTime.now().difference(post.savedDate).inDays > 30
      ).toList();
      
      neverOpened.addAll(oldPosts.where((post) => post.tags.isEmpty));
      
      if (neverOpened.isNotEmpty) {
        advancedAnalytics.trackAdvancedEvent(
          AdvancedEventType.contentNeverOpened,
          properties: {
            'never_opened_count': neverOpened.length,
            'total_old_posts': oldPosts.length,
            'abandonment_rate': neverOpened.length / allPosts.length,
          },
        );
      }
      
    } catch (e) {
      print('ERRORE: Rilevamento contenuti mai aperti fallito: $e');
    }
    
    return neverOpened;
  }
  
  Map<String, double> calculateContentEngagement() {
    final engagement = <String, double>{};
    
    try {
      for (var post in allPosts) {
        double score = 0.0;
        
        score += post.tags.length * 0.2;
        
        final daysSinceSaved = DateTime.now().difference(post.savedDate).inDays;
        if (daysSinceSaved <= 7) score += 0.5;
        
        if (post.imageUrl != null) score += 0.3;
        
        engagement[post.id] = score.clamp(0.0, 1.0);
      }
    } catch (e) {
      print('ERRORE: Calcolo engagement fallito: $e');
    }
    
    return engagement;
  }
  
  // ============================================================================
  // STATISTICHE
  // ============================================================================
  
  Map<String, int> getAccountStats() {
    int totalFolders = folders.length;
    
    void countSubfolders(MockFolder folder) {
      totalFolders += folder.children.length;
      for (var child in folder.children) {
        countSubfolders(child);
      }
    }
    
    for (var folder in folders) {
      countSubfolders(folder);
    }
    
    return {
      'totalPosts': allPosts.length,
      'totalFolders': totalFolders,
    };
  }
  
  Future<Map<String, int>> getRealAccountStats() async {
    try {
      return await executeWithRetry(() async {
        final realFolders = await DataService.instance.getFolders();
        final realPosts = await DataService.instance.getPosts();
        
        return {
          'totalPosts': realPosts.length,
          'totalFolders': realFolders.length,
          'mockPosts': allPosts.length,
          'mockFolders': folders.length,
        };
      }, 'get_real_account_stats');
    } catch (e) {
      return getAccountStats();
    }
  }
  
  Future<Map<String, dynamic>> verifyDataIntegrity() async {
    try {
      return await executeWithRetry(() async {
        final realFolders = await DataService.instance.getFolders();
        final realPosts = await DataService.instance.getPosts();
        
        final userFoldersInDb = realFolders.where((f) => !f.isDefault).length;
        
        // 🔥 FIX: Conta tutte le cartelle ricorsivamente nell'albero in memoria
        int countAllFolders(MockFolder folder) {
          int count = folder.isSpecial ? 0 : 1;
          for (var child in folder.children) {
            count += countAllFolders(child);
          }
          return count;
        }
        
        int userFoldersInMemory = 0;
        for (var folder in folders) {
          userFoldersInMemory += countAllFolders(folder);
        }
        
        final hasDefaultInDb = realFolders.any((f) => f.isDefault);
        final hasSpecialInMemory = folders.any((f) => f.isSpecial);
        
        final isConsistent = userFoldersInDb == userFoldersInMemory && 
                           realPosts.length == allPosts.length &&
                           hasDefaultInDb && hasSpecialInMemory;
        
        final result = {
          'status': 'success',
          'foldersInDatabase': realFolders.length,
          'foldersInMemoryTree': userFoldersInMemory + (hasSpecialInMemory ? 1 : 0),
          'rootFoldersInMemory': folders.length,
          'postsInDatabase': realPosts.length,
          'postsInMemory': allPosts.length,
          'isConsistent': isConsistent,
          'healthStatus': currentHealth.status.toString(),
        };
        
        if (isConsistent) {
          updateHealthStatus(ServiceHealthStatus.healthy);
        } else {
          // Se non è consistente, ma abbiamo dati, usiamo 'degraded' invece di 'error'
          updateHealthStatus(ServiceHealthStatus.degraded, 
                           errorMessage: 'Data integrity issues detected: DB $userFoldersInDb vs Memory $userFoldersInMemory folders');
        }
        
        return result;
      }, 'verify_data_integrity');
    } catch (e) {
      return {
        'status': 'error',
        'error': e.toString(),
        'isConsistent': false,
      };
    }
  }
  
  // ============================================================================
  // UTILITY
  // ============================================================================
  
  String? extractSocialNetwork(String url) {
    try {
      final uri = Uri.parse(url);
      final domain = uri.host.toLowerCase();
      
      if (domain.contains('instagram.com')) return 'Instagram';
      if (domain.contains('facebook.com')) return 'Facebook';
      if (domain.contains('twitter.com') || domain.contains('x.com')) return 'Twitter/X';
      if (domain.contains('youtube.com') || domain.contains('youtu.be')) return 'YouTube';
      if (domain.contains('tiktok.com')) return 'TikTok';
      if (domain.contains('linkedin.com')) return 'LinkedIn';
      if (domain.contains('pinterest.com')) return 'Pinterest';
      if (domain.contains('reddit.com')) return 'Reddit';
      if (domain.contains('github.com')) return 'GitHub';
      
      return domain;
    } catch (e) {
      return null;
    }
  }
  
  String buildHierarchicalPathForTracking(MockFolder folder) {
    if (folder.isSpecial) return folder.name;
    
    List<String> pathParts = [];
    MockFolder? current = folder;
    
    while (current != null && !current.isSpecial) {
      pathParts.insert(0, current.name);
      current = current.parent;
    }
    
    return pathParts.join(' › ');
  }
  
  Map<String, dynamic> getSystemDiagnostics() {
    return {
      'service_info': {
        'initialized': isInitialized,
        'authenticated': isAuthenticated,
        'current_user': currentUserId,
        'folders_count': folders.length,
        'posts_count': allPosts.length,
      },
      'health_metrics': currentHealth.toMap(),
      'cache_info': {
        'cached_users': userFoldersCache.keys.toList(),
        'cache_valid': currentUserId != null ? isCacheValid(currentUserId!) : null,
      },
      'callback_system': {
        'dataservice_callback_registered': isDataServiceCallbackRegistered,
        'ui_callbacks_count': uiUpdateCallbacks.length,
      },
    };
  }
}