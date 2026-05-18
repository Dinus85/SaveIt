// lib/services/migration_script.dart
// Script di migrazione da nomi concatenati a parentId
// ESEGUIRE UNA SOLA VOLTA per utente esistente

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';

class FolderMigrationScript {
  
  /// Esegui migrazione per l'utente corrente
  static Future<void> migrateFoldersToParentId() async {
    print('========== MIGRAZIONE CARTELLE A PARENTID ==========');
    
    try {
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        throw Exception('Utente non autenticato');
      }
      
      print('Migrando cartelle per utente: ${firebaseUser.uid}');
      
      final firestore = FirebaseFirestore.instance;
      final foldersCollection = firestore
          .collection('users')
          .doc(firebaseUser.uid)
          .collection('folders');
      
      // PASSO 1: Leggi tutte le cartelle esistenti
      final snapshot = await foldersCollection.get();
      print('Trovate ${snapshot.docs.length} cartelle da migrare');
      
      // PASSO 2: Identifica cartelle con nomi concatenati (contengono "›")
      final Map<String, DocumentSnapshot> foldersToMigrate = {};
      final Map<String, DocumentSnapshot> rootFolders = {};
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final name = data['name'] as String;
        final isDefault = data['isDefault'] as bool? ?? false;
        
        if (!isDefault) {
          if (name.contains(' › ')) {
            foldersToMigrate[doc.id] = doc;
            print('Cartella da migrare: $name (ID: ${doc.id})');
          } else {
            rootFolders[doc.id] = doc;
            print('Cartella root (OK): $name (ID: ${doc.id})');
          }
        }
      }
      
      if (foldersToMigrate.isEmpty) {
        print('Nessuna cartella da migrare. Tutte le cartelle usano già parentId.');
        return;
      }
      
      print('\n${foldersToMigrate.length} cartelle da migrare');
      print('${rootFolders.length} cartelle root già OK');
      
      // PASSO 3: Migra le cartelle concatenate
      final batch = firestore.batch();
      int migratedCount = 0;
      
      // Map per tracciare ID delle cartelle create
      final Map<String, String> pathToId = {};
      
      // Aggiungi root folders alla map
      for (var entry in rootFolders.entries) {
        final data = entry.value.data() as Map<String, dynamic>;
        pathToId[data['name']] = entry.key;
      }
      
      // Ordina cartelle per profondità (meno › = più shallow)
      final sortedFolders = foldersToMigrate.entries.toList()
        ..sort((a, b) {
          final aDepth = (a.value.data() as Map<String, dynamic>)['name'].split(' › ').length;
          final bDepth = (b.value.data() as Map<String, dynamic>)['name'].split(' › ').length;
          return aDepth.compareTo(bDepth);
        });
      
      for (var entry in sortedFolders) {
        final docId = entry.key;
        final doc = entry.value;
        final data = doc.data() as Map<String, dynamic>;
        final fullName = data['name'] as String;
        
        print('\nProcessando: $fullName');
        
        // Separa il path
        final parts = fullName.split(' › ');
        final folderName = parts.last;
        final parentPath = parts.sublist(0, parts.length - 1).join(' › ');
        
        print('  Nome: $folderName');
        print('  Parent path: $parentPath');
        
        // Trova parent ID
        String? parentId;
        if (parentPath.isNotEmpty) {
          parentId = pathToId[parentPath];
          
          if (parentId == null) {
            print('  WARNING: Parent non trovato per "$parentPath", creando come root');
          } else {
            print('  Parent ID trovato: $parentId');
          }
        }
        
        // Aggiorna il documento
        batch.update(doc.reference, {
          'name': folderName,  // Solo il nome, non il path completo
          'parentId': parentId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        
        // Aggiungi alla map per future riferimenti
        pathToId[fullName] = docId;
        
        migratedCount++;
        print('  ✓ Migrata: $folderName (parentId: $parentId)');
      }
      
      // PASSO 4: Esegui batch write
      print('\nCommittando ${migratedCount} modifiche...');
      await batch.commit();
      
      print('✓ MIGRAZIONE COMPLETATA CON SUCCESSO');
      print('Cartelle migrate: $migratedCount');
      print('=========================================');
      
    } catch (e, stackTrace) {
      print('ERRORE MIGRAZIONE: $e');
      print('Stack trace: $stackTrace');
      throw e;
    }
  }
  
  /// Verifica migrazione
  static Future<void> verifyMigration() async {
    print('\n========== VERIFICA MIGRAZIONE ==========');
    
    try {
      final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        throw Exception('Utente non autenticato');
      }
      
      final firestore = FirebaseFirestore.instance;
      final foldersCollection = firestore
          .collection('users')
          .doc(firebaseUser.uid)
          .collection('folders');
      
      final snapshot = await foldersCollection.get();
      
      int withParentId = 0;
      int withConcatenatedNames = 0;
      int rootFolders = 0;
      int defaultFolders = 0;
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final name = data['name'] as String;
        final isDefault = data['isDefault'] as bool? ?? false;
        final parentId = data['parentId'] as String?;
        
        if (isDefault) {
          defaultFolders++;
        } else if (name.contains(' › ')) {
          withConcatenatedNames++;
          print('⚠️  Cartella non migrata: $name');
        } else if (parentId != null) {
          withParentId++;
        } else {
          rootFolders++;
        }
      }
      
      print('Cartelle totali: ${snapshot.docs.length}');
      print('Cartelle default: $defaultFolders');
      print('Cartelle root: $rootFolders');
      print('Cartelle con parentId: $withParentId');
      print('Cartelle con nomi concatenati: $withConcatenatedNames');
      
      if (withConcatenatedNames == 0) {
        print('✓ MIGRAZIONE VERIFICATA - Tutte le cartelle usano parentId');
      } else {
        print('⚠️  ATTENZIONE: Ci sono ancora $withConcatenatedNames cartelle da migrare');
      }
      
      print('=====================================\n');
      
    } catch (e) {
      print('ERRORE VERIFICA: $e');
      throw e;
    }
  }
}