# 📚 Documentazione Sistema Gestione Cartelle e Post

## 🎯 Panoramica

Questo documento descrive il funzionamento completo del sistema di gestione cartelle, sottocartelle e anteprime dell'applicazione SaveIt.

---

## 📊 Architettura del Sistema

### **Prima: Sistema Frammentato** ❌
Il codice era diviso in **8 file separati**:
- `folder_service_base.dart` (singleton, cache, auth)
- `folder_service_sync.dart` (sincronizzazione)
- `folder_service_crud.dart` (create/delete)
- `folder_service_search.dart` (ricerca)
- `folder_service_sharing.dart` (condivisione)
- `folder_service_analytics.dart` (tracking)
- `folder_service_models.dart` (modelli)
- `folder_service.dart` (entry point)

### **Ora: Sistema Unificato** ✅
Tutto consolidato in:
- `lib/services/folder_management_unified.dart` ⭐
- Organizzato in **7 sezioni logiche**
- Facile da mantenere e comprendere

---

## 🏗️ Struttura dei Dati

### 1. **Modelli Database** (Firebase Firestore)

```dart
class Folder {
  String id;           // ID univoco Firebase
  String name;         // Nome cartella
  String color;        // Colore (formato HEX)
  String? parentId;    // ⭐ ID del parent (null = root)
  bool isDefault;      // true solo per "Tutti"
  DateTime createdAt;
  DateTime? updatedAt;
}
```

**Esempio di gerarchia nel database:**
```
users/{userId}/folders/
  ├─ {id1}: { name: "Tech", parentId: null }
  ├─ {id2}: { name: "Flutter", parentId: {id1} }
  └─ {id3}: { name: "Tips", parentId: {id2} }
```

### 2. **Modelli UI** (Struttura ad Albero)

```dart
class MockFolder {
  String name;
  int level;                    // 0 = root, 1 = subfolder, etc.
  MockFolder? parent;           // Riferimento al parent
  List<MockFolder> children;    // Lista sottocartelle
  bool isSpecial;               // true solo per "Tutti"
  String count;                 // "5 Post" o "3 cartelle • 5 Post"
  Color color;
}
```

**Esempio di struttura UI:**
```
Tutti (isSpecial: true, level: 0)
Tech (level: 0, parent: null)
  └─ Flutter (level: 1, parent: Tech)
      └─ Tips (level: 2, parent: Flutter)
```

### 3. **Post**

```dart
class SavedPost {  // Database
  String id;
  String url;
  String title;
  String description;
  String? imageUrl;         // ⭐ URL anteprima
  List<String> tags;
  String folderId;          // ⭐ ID cartella di appartenenza
  DateTime createdAt;
}

class MockPost {  // UI
  String id;
  String title;
  String url;
  String? imageUrl;
  MockFolder? sourceFolder;  // ⭐ Riferimento alla cartella UI
  DateTime savedDate;
}
```

---

## 🔧 Funzionalità Principali

### **SECTION 1: Creazione Gerarchia Cartelle**

#### Creare una gerarchia completa da un path:

```dart
// Crea "Tech → Flutter → Tips"
final folderId = await FolderHierarchyManager.createHierarchyFromPath(
  "Tech › Flutter › Tips"
);
// Returns: ID Firebase di "Tips"
```

**Come funziona:**
1. Parse del path in parti: `["Tech", "Flutter", "Tips"]`
2. Per ogni livello:
   - Cerca se la cartella esiste già
   - Se esiste, usa il suo ID come parent per il prossimo livello
   - Se non esiste, creala con `parentId` appropriato
3. Restituisce l'ID dell'ultima cartella creata

#### Creare una cartella root:

```dart
await FolderOperations.createRootFolder("Tech");
```

Crea una cartella con `parentId = null`

#### Creare una sottocartella:

```dart
MockFolder techFolder = ...; // Cartella parent nell'UI
await FolderOperations.createSubfolder(techFolder, "Flutter");
```

1. Trova l'ID database del parent
2. Crea cartella con `parentId = parent.id`

---

### **SECTION 2: Sincronizzazione Database ↔ UI**

#### Sincronizzare cartelle dal database:

```dart
// Carica dal database
List<Folder> dbFolders = await DataService.instance.getFolders();

// Converti in struttura UI ad albero
List<MockFolder> uiFolders = await FolderSynchronizationManager
    .syncFoldersFromDatabase(dbFolders);
```

**Algoritmo di sincronizzazione:**

1. **Crea cartella "Tutti"** (speciale)
2. **Crea tutte le cartelle root** (`parentId == null`)
   - `level = 0`
   - `parent = null`
3. **Crea sottocartelle in ordine di profondità** (iterativo):
   - Per ogni cartella con `parentId != null`:
     - Cerca il parent nella map
     - Se trovato, crea la sottocartella:
       - `level = parent.level + 1`
       - `parent = parentMockFolder`
       - Aggiungi a `parent.children`

**Risultato:** Struttura ad albero completa pronta per l'UI

#### Trovare cartella database da MockFolder UI:

```dart
List<Folder> dbFolders = await DataService.instance.getFolders();
MockFolder uiFolder = ...; // Dalla UI

Folder? dbFolder = FolderSynchronizationManager
    .findDatabaseFolderFromMock(dbFolders, uiFolder);
```

**Algoritmo:**
1. Costruisce il path dalla MockFolder alla root: `["Tech", "Flutter", "Tips"]`
2. Naviga nel database seguendo `parentId`:
   - Cerca "Tech" con `parentId == null`
   - Cerca "Flutter" con `parentId == Tech.id`
   - Cerca "Tips" con `parentId == Flutter.id`
3. Restituisce l'ultima Folder trovata

---

### **SECTION 3: Anteprime Cartelle**

#### Ottenere immagini per anteprima:

```dart
MockFolder folder = ...; // Cartella target
List<MockPost> allPosts = ...; // Tutti i post

FolderPreviewStats stats = FolderPreviewManager
    .getFolderPreviewImages(folder, allPosts, maxImages: 4);

print(stats.imageUrls);  // ["url1", "url2", "url3", "url4"]
print(stats.totalImagesAvailable);  // 15
print(stats.hasEnoughForGrid);  // true se >= 2 immagini
```

**Come funziona:**

1. **Se cartella "Tutti"**: Prendi tutti i post con immagini
2. **Se cartella normale**:
   - Raccogli post dalla cartella stessa
   - Raccogli post dalle sottocartelle (ricorsivo)
3. Ordina per data (più recenti prima)
4. Prendi i primi N post
5. Estrai gli URL delle immagini

#### Usare le anteprime nel widget:

```dart
// In folder_card.dart
Widget _buildFolderPreview() {
  final stats = FolderPreviewManager.getFolderPreviewImages(
    folder,
    allPosts,
    maxImages: 4,
  );
  
  if (stats.imageUrls.isNotEmpty) {
    return _PostImagesGrid(imageUrls: stats.imageUrls);
  } else {
    return _buildDefaultPreview();
  }
}
```

**Layout anteprime:**
- **1 immagine**: Occupa tutto lo spazio
- **2 immagini**: Disposte verticalmente
- **3 immagini**: 2 in alto, 1 in basso
- **4+ immagini**: Griglia 2×2

---

### **SECTION 4: Gestione Post**

#### Salvare un post in una cartella:

```dart
// Ottieni l'ID della cartella target
MockFolder targetFolder = ...;
List<Folder> dbFolders = await DataService.instance.getFolders();

Folder? dbFolder = FolderSynchronizationManager
    .findDatabaseFolderFromMock(dbFolders, targetFolder);

// Salva il post
SavedPost post = await PostManagement.savePostToFolder(
  url: "https://example.com",
  title: "Titolo",
  description: "Descrizione",
  imageUrl: "https://example.com/image.jpg",  // ⭐ Per anteprima
  tags: ["flutter", "tips"],
  folderId: dbFolder!.id,  // ⭐ Collega alla cartella
);
```

#### Spostare un post:

```dart
SavedPost post = ...;
String newFolderId = "xyz123";

await PostManagement.movePostToFolder(post, newFolderId);
```

#### Sincronizzare post dal database:

```dart
List<SavedPost> dbPosts = await DataService.instance.getPosts();
List<Folder> dbFolders = await DataService.instance.getFolders();
List<MockFolder> uiFolders = [...]; // Già sincronizzate

List<MockPost> uiPosts = await PostManagement.syncPostsFromDatabase(
  dbPosts,
  dbFolders,
  uiFolders,
);
```

**Algoritmo:**
1. Crea map: `Folder.id → MockFolder`
2. Per ogni post nel database:
   - Trova la cartella target usando `post.folderId`
   - Trova la corrispondente MockFolder nella map
   - Crea MockPost collegato a MockFolder
3. Restituisce lista di MockPost pronti per l'UI

---

### **SECTION 5: Operazioni CRUD**

#### Rinominare una cartella:

```dart
MockFolder folder = ...;
await FolderOperations.renameFolder(folder, "Nuovo Nome");
```

1. Trova cartella nel database
2. Aggiorna nel database
3. Aggiorna in memoria (`folder.name = "Nuovo Nome"`)

#### Eliminare una cartella:

```dart
MockFolder folder = ...;
await FolderOperations.deleteFolder(folder);
```

1. Trova tutti i post nella cartella
2. Sposta i post in "Tutti"
3. Elimina la cartella dal database
4. Rimuove dalla struttura UI

#### Spostare una cartella:

```dart
MockFolder folder = ...;
MockFolder newParent = ...;

await FolderOperations.moveFolder(folder, newParent);
```

1. Trova cartelle nel database
2. Aggiorna `parentId` nel database
3. Aggiorna struttura UI:
   - Rimuove da `oldParent.children`
   - Aggiunge a `newParent.children`
   - Aggiorna `level`

---

## 🔄 Flusso Completo: Esempio Pratico

### **Scenario: Utente salva un post in "Tech › Flutter › Tips"**

#### Step 1: Creazione gerarchia (se non esiste)

```dart
// Cartella non esiste, creala
String tipsFolderId = await FolderHierarchyManager
    .createHierarchyFromPath("Tech › Flutter › Tips");
```

**Cosa succede:**
1. Cerca "Tech" root → **non esiste** → crea (ID: `abc123`, parentId: `null`)
2. Cerca "Flutter" child di Tech → **non esiste** → crea (ID: `def456`, parentId: `abc123`)
3. Cerca "Tips" child di Flutter → **non esiste** → crea (ID: `ghi789`, parentId: `def456`)
4. Restituisce `"ghi789"`

#### Step 2: Salvataggio post

```dart
SavedPost post = await PostManagement.savePostToFolder(
  url: "https://flutter.dev/docs",
  title: "Flutter Best Practices",
  imageUrl: "https://flutter.dev/image.jpg",
  folderId: tipsFolderId,  // "ghi789"
);
```

**Nel database:**
```
posts/{postId}: {
  url: "https://flutter.dev/docs",
  title: "Flutter Best Practices",
  imageUrl: "https://flutter.dev/image.jpg",
  folderId: "ghi789",  // Collega a "Tips"
  createdAt: Timestamp
}
```

#### Step 3: Sincronizzazione UI

```dart
// Ricarica tutto
List<Folder> dbFolders = await DataService.instance.getFolders();
List<SavedPost> dbPosts = await DataService.instance.getPosts();

// Sincronizza cartelle
List<MockFolder> uiFolders = await FolderSynchronizationManager
    .syncFoldersFromDatabase(dbFolders);

// Sincronizza post
List<MockPost> uiPosts = await PostManagement.syncPostsFromDatabase(
  dbPosts,
  dbFolders,
  uiFolders,
);
```

**Risultato nella UI:**
```
Tutti (10 Post)
└─ Tech (1 cartella • 1 Post)
    └─ Flutter (1 cartella • 1 Post)
        └─ Tips (1 Post)  ⭐ Anteprima: mostra immagine del post
```

#### Step 4: Generazione anteprima

```dart
MockFolder tipsFolder = ...; // Dalla UI

FolderPreviewStats stats = FolderPreviewManager
    .getFolderPreviewImages(tipsFolder, uiPosts);

// stats.imageUrls = ["https://flutter.dev/image.jpg"]
// Widget mostra l'immagine come anteprima della cartella
```

---

## 🎨 Widget: Folder Card con Anteprima

```dart
// In folder_card.dart
class MockFolderCard extends StatelessWidget {
  final MockFolder folder;
  
  Widget _buildFolderPreview() {
    final stats = UnifiedFolderManager.preview
        .getFolderPreviewImages(folder, allPosts, maxImages: 4);
    
    if (stats.imageUrls.isNotEmpty) {
      // Mostra griglia immagini
      return _PostImagesGrid(
        imageUrls: stats.imageUrls,
        borderRadius: BorderRadius.circular(12),
      );
    } else {
      // Mostra pattern di default
      return _buildDefaultPattern();
    }
  }
}
```

**Layout anteprime:**
```
╔═══════════════╗
║ 1 immagine    ║  Singola immagine
║               ║
╚═══════════════╝

╔═══════════════╗
║     Img 1     ║  Due immagini
╠═══════════════╣  verticali
║     Img 2     ║
╚═══════════════╝

╔═══════╦═══════╗
║ Img 1 ║ Img 2 ║  3 immagini:
╠═══════╩═══════╣  2 sopra, 1 sotto
║     Img 3     ║
╚═══════════════╝

╔═══════╦═══════╗
║ Img 1 ║ Img 2 ║  4+ immagini:
╠═══════╬═══════╣  Griglia 2×2
║ Img 3 ║ Img 4 ║
╚═══════╩═══════╝
```

---

## 🛠️ Come Usare il Sistema Unificato

### Importa il manager:

```dart
import 'package:saveit/services/folder_management_unified.dart';
```

### Esempi di utilizzo:

```dart
// === CREAZIONE CARTELLE ===

// Cartella root
await UnifiedFolderManager.operations.createRootFolder("Tech");

// Sottocartella
MockFolder tech = ...;
await UnifiedFolderManager.operations.createSubfolder(tech, "Flutter");

// Gerarchia completa
String id = await UnifiedFolderManager.hierarchy
    .createHierarchyFromPath("Tech › Flutter › Tips");


// === SINCRONIZZAZIONE ===

// Cartelle
List<Folder> dbFolders = await DataService.instance.getFolders();
List<MockFolder> uiFolders = await UnifiedFolderManager.sync
    .syncFoldersFromDatabase(dbFolders);

// Post
List<SavedPost> dbPosts = await DataService.instance.getPosts();
List<MockPost> uiPosts = await UnifiedFolderManager.posts
    .syncPostsFromDatabase(dbPosts, dbFolders, uiFolders);


// === ANTEPRIME ===

FolderPreviewStats stats = UnifiedFolderManager.preview
    .getFolderPreviewImages(folder, allPosts, maxImages: 4);

bool canShow = UnifiedFolderManager.preview
    .canShowImagePreview(folder, allPosts);


// === SALVATAGGIO POST ===

await UnifiedFolderManager.posts.savePostToFolder(
  url: "https://example.com",
  title: "Titolo",
  imageUrl: "https://example.com/img.jpg",
  folderId: folderId,
);


// === OPERAZIONI CARTELLE ===

// Rinomina
await UnifiedFolderManager.operations.renameFolder(folder, "Nuovo Nome");

// Elimina
await UnifiedFolderManager.operations.deleteFolder(folder);

// Sposta
await UnifiedFolderManager.operations.moveFolder(folder, newParent);


// === UTILITY ===

// Conta post
int count = UnifiedFolderManager.utils.countPostsInFolder(folder, allPosts);

// Aggiorna conteggi
UnifiedFolderManager.utils.updateAllFolderCounts(folders, allPosts);

// Stampa struttura (debug)
UnifiedFolderManager.utils.printFolderStructure(folders);
```

---

## 🐛 Debug e Diagnostica

### Stampa struttura cartelle:

```dart
UnifiedFolderManager.utils.printFolderStructure(folders);
```

Output:
```
├─ Tech (livello 0)
│  ├─ Flutter (livello 1)
│  │  └─ Tips (livello 2)
│  └─ React (livello 1)
├─ Ricette (livello 0)
```

### Verifica statistiche anteprima:

```dart
Map<String, dynamic> stats = UnifiedFolderManager.preview
    .getFolderImageStats(folder, allPosts);

print(stats);
// {
//   'totalImages': 15,
//   'recentImages': 4,
//   'hasEnoughForGrid': true,
//   'canShowPreview': true
// }
```

### Costruisci path cartella:

```dart
String path = UnifiedFolderManager.hierarchy.buildFolderPath(folder);
print(path);  // "Home › Tech › Flutter › Tips"
```

---

## 📝 Note Tecniche Importanti

### **1. Differenza tra Folder e MockFolder**

| Aspetto | `Folder` (Database) | `MockFolder` (UI) |
|---------|---------------------|-------------------|
| Struttura | Lista piatta con `parentId` | Albero con `parent/children` |
| Livello | Calcolato | Esplicito (`level`) |
| Uso | Firestore storage | Rendering UI |
| Conversione | → `MockFolder` via sync | → `Folder` via findDatabaseFolderFromMock |

### **2. Gerarchia Profondità**

Il sistema supporta gerarchie di profondità illimitata, ma l'UI potrebbe limitarle:

```dart
// In constants.dart
class AppConstants {
  static const int maxFolderDepth = 3;  // Modifica qui
}
```

### **3. Cache e Performance**

- La cache viene invalidata automaticamente dopo operazioni CRUD
- `_refreshDatabaseCache()` forza reload da Firestore
- Le anteprime vengono calcolate al volo (considera di cachare se lente)

### **4. Gestione Errori**

Tutte le operazioni possono lanciare eccezioni:

```dart
try {
  await UnifiedFolderManager.operations.createRootFolder("Tech");
} catch (e) {
  print('Errore creazione cartella: $e');
  // Gestisci errore (mostra snackbar, etc.)
}
```

---

## 🚀 Migrazione dal Sistema Vecchio

Se stai migrando dal sistema precedente diviso in 8 file:

### 1. Sostituisci gli import:

**Prima:**
```dart
import 'package:saveit/services/folder_service_crud.dart';
import 'package:saveit/services/folder_service_sync.dart';
import 'package:saveit/services/folder_service_search.dart';
```

**Dopo:**
```dart
import 'package:saveit/services/folder_management_unified.dart';
```

### 2. Sostituisci le chiamate:

**Prima:**
```dart
await folderServiceCRUD.createPersistentFolder("Tech");
await folderServiceSync.syncFoldersFromDataServiceWithParentId(folders);
final images = folderServiceSearch.getLastPostImagesForFolder(folder);
```

**Dopo:**
```dart
await UnifiedFolderManager.operations.createRootFolder("Tech");
await UnifiedFolderManager.sync.syncFoldersFromDatabase(folders);
final stats = UnifiedFolderManager.preview.getFolderPreviewImages(folder, posts);
final images = stats.imageUrls;
```

### 3. I vecchi file possono essere eliminati (dopo verifica):
- ✅ `folder_service_crud.dart`
- ✅ `folder_service_sync.dart`
- ✅ `folder_service_search.dart`
- ⚠️ Mantieni `folder_service.dart` se usato da altre parti dell'app
- ⚠️ Mantieni `folder_service_base.dart` per singleton pattern

---

## 📚 Riferimenti

- **File principale**: `lib/services/folder_management_unified.dart`
- **Modelli**: `lib/models.dart` e `lib/models/folder.dart`
- **Widget anteprime**: `lib/widgets/folder_card.dart`
- **Data Service**: `lib/data_service.dart`

---

## ✅ Checklist Implementazione

- [x] Creazione cartelle root
- [x] Creazione sottocartelle
- [x] Creazione gerarchia da path
- [x] Sincronizzazione database → UI
- [x] Sincronizzazione post
- [x] Generazione anteprime con immagini
- [x] Layout anteprime responsive (1/2/3/4 immagini)
- [x] Operazioni CRUD (rename, delete, move)
- [x] Utility conteggi e statistiche
- [x] Debug e diagnostica

---

## 💡 Suggerimenti per il Futuro

1. **Cache Anteprime**: Considera di cachare le anteprime calcolate per migliorare performance
2. **Lazy Loading**: Per gerarchie molto profonde, considera lazy loading delle sottocartelle
3. **Drag & Drop**: Implementa drag & drop per spostare cartelle visualmente
4. **Bulk Operations**: Aggiungi operazioni bulk (es. sposta multipli post)
5. **Undo/Redo**: Considera di implementare undo/redo per operazioni critiche

---

**Documento creato**: Dicembre 2025  
**Versione**: 1.0  
**Autore**: Sistema di consolidamento codice



