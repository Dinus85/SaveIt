import 'package:flutter/material.dart';
import '../models/folder.dart';
import '../utils/constants.dart';

// Utility class per la gestione delle cartelle
class FolderManagement {
  
  // Trova una cartella nella gerarchia
  static MockFolder? findFolderInHierarchy(MockFolder targetFolder, List<MockFolder> folders) {
    MockFolder? findInList(List<MockFolder> folderList) {
      for (var folder in folderList) {
        if (folder == targetFolder) return folder;
        final found = findInList(folder.children);
        if (found != null) return found;
      }
      return null;
    }
    return findInList(folders);
  }

  // Rimuove una cartella dalla gerarchia
  static bool removeFolderFromHierarchy(MockFolder folderToRemove, List<MockFolder> folders) {
    bool removeFromList(List<MockFolder> folderList) {
      for (int i = 0; i < folderList.length; i++) {
        if (folderList[i] == folderToRemove) {
          folderList.removeAt(i);
          return true;
        }
        if (removeFromList(folderList[i].children)) {
          return true;
        }
      }
      return false;
    }
    return removeFromList(folders);
  }

  // Verifica se una cartella Ã¨ discendente di un'altra
  static bool isDescendantOf(MockFolder folder, MockFolder ancestor) {
    MockFolder? current = folder.parent;
    while (current != null) {
      if (current == ancestor) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  // Calcola la profonditÃ  massima di una cartella
  static int getMaxDepth(MockFolder folder) {
    if (folder.children.isEmpty) {
      return 0;
    }
    int maxChildDepth = 0;
    for (var child in folder.children) {
      int childDepth = getMaxDepth(child);
      if (childDepth > maxChildDepth) {
        maxChildDepth = childDepth;
      }
    }
    return maxChildDepth + 1;
  }

  // Aggiorna ricorsivamente i livelli delle sottocartelle
  static void updateSubfolderLevels(MockFolder folder) {
    for (var child in folder.children) {
      child.level = folder.level + 1;
      updateSubfolderLevels(child);
    }
  }

  // Calcola il numero totale di post in tutte le cartelle
  static int calculateTotalPosts(List<MockFolder> folders) {
    int total = 0;
    
    int countFolderPosts(MockFolder folder) {
      int count = 0;
      if (folder.count.contains('Post')) {
        final match = RegExp(r'(\d+)').firstMatch(folder.count);
        if (match != null) {
          count += int.parse(match.group(1)!);
        }
      }
      
      for (var child in folder.children) {
        count += countFolderPosts(child);
      }
      
      return count;
    }
    
    for (var folder in folders) {
      if (!folder.isSpecial) {
        total += countFolderPosts(folder);
      }
    }
    
    return total;
  }

  // Cerca cartelle per nome
  static List<MockFolder> searchFolders(String query, List<MockFolder> folders) {
    List<MockFolder> results = [];
    
    void searchInFolder(MockFolder folder, [String path = '']) {
      final currentPath = path.isEmpty ? folder.name : '$path > ${folder.name}';
      
      // Cerca nel nome della cartella
      if (folder.name.toLowerCase().contains(query.toLowerCase())) {
        results.add(MockFolder(
          name: currentPath,
          count: folder.count,
          color: folder.color,
          level: folder.level,
          originalFolder: folder,
        ));
      }
      
      // Cerca nelle sottocartelle
      for (var child in folder.children) {
        searchInFolder(child, currentPath);
      }
    }
    
    for (var folder in folders) {
      searchInFolder(folder);
    }
    
    return results;
  }

  // Capitalizza la prima lettera di una stringa
  static String capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  // Ottiene un colore casuale per le cartelle
  static Color getRandomColor() {
    final colors = [
      Colors.orange.shade200,
      Colors.orange.shade100,
      Colors.pink.shade200,
      Colors.purple.shade200,
      Colors.blue.shade200,
      Colors.green.shade200,
      Colors.yellow.shade200,
      Colors.red.shade200,
    ];
    colors.shuffle();
    return colors.first;
  }

  // Costruisce il breadcrumb del percorso della cartella
  static String buildBreadcrumb(MockFolder folder) {
    List<String> path = [];
    MockFolder? current = folder.parent;
    
    // Risali la gerarchia fino alla radice
    while (current != null) {
      if (!current.isSpecial) { // Non includere "Tutti" nel breadcrumb
        path.insert(0, current.name);
      }
      current = current.parent;
    }
    
    if (path.isEmpty) {
      return 'Cartella principale';
    }
    
    return path.join(' > ');
  }

  // Valida se Ã¨ possibile spostare una cartella in una destinazione
  static bool canMoveFolder(MockFolder folderToMove, MockFolder? destination) {
    if (destination == null) {
      return true; // Spostamento alla radice sempre permesso
    }
    
    // Non puoi spostare una cartella dentro se stessa o in un suo discendente
    if (folderToMove == destination || isDescendantOf(destination, folderToMove)) {
      return false;
    }
    
    // CORRETTO: Verifica che non superi il livello massimo usando AppConstants
    final maxLevelAfterMove = destination.level + 1 + getMaxDepth(folderToMove);
    return maxLevelAfterMove <= AppConstants.maxFolderLevels;
  }
}