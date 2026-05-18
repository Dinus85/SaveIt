# 🎨 Diagrammi Sistema Gestione Cartelle

## 📊 Architettura Generale

```
┌─────────────────────────────────────────────────────────────────┐
│                     UNIFIED FOLDER MANAGER                       │
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  Hierarchy   │  │     Sync     │  │   Preview    │          │
│  │   Manager    │  │   Manager    │  │   Manager    │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │     Post     │  │  Operations  │  │    Utils     │          │
│  │  Management  │  │    (CRUD)    │  │              │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  DataService    │
                    │   (Firebase)    │
                    └─────────────────┘
                              │
                              ▼
                ┌─────────────────────────────┐
                │   Firebase Firestore DB     │
                │                             │
                │  users/{uid}/               │
                │    ├─ folders/              │
                │    │   ├─ {id1} (Tech)      │
                │    │   ├─ {id2} (Flutter)   │
                │    │   └─ {id3} (Tips)      │
                │    │                         │
                │    └─ posts/                │
                │        ├─ {postId1}         │
                │        └─ {postId2}         │
                └─────────────────────────────┘
```

---

## 🗂️ Struttura Database vs UI

### Database (Firestore) - Lista Piatta con parentId

```
Collection: users/{userId}/folders/

┌─────────────────────────────────────────────────────────────┐
│ Document: abc123                                             │
│ {                                                            │
│   name: "Tech",                                             │
│   parentId: null,           ← Root folder                   │
│   color: "#4285F4",                                         │
│   isDefault: false                                          │
│ }                                                            │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Document: def456                                             │
│ {                                                            │
│   name: "Flutter",                                          │
│   parentId: "abc123",       ← Child di Tech                 │
│   color: "#02569B",                                         │
│   isDefault: false                                          │
│ }                                                            │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Document: ghi789                                             │
│ {                                                            │
│   name: "Tips",                                             │
│   parentId: "def456",       ← Child di Flutter              │
│   color: "#66BB6A",                                         │
│   isDefault: false                                          │
│ }                                                            │
└─────────────────────────────────────────────────────────────┘
```

### UI (MockFolder) - Struttura ad Albero

```
MockFolder: Tutti
├─ name: "Tutti"
├─ level: 0
├─ isSpecial: true
├─ parent: null
└─ children: []

MockFolder: Tech
├─ name: "Tech"
├─ level: 0
├─ parent: null
├─ children: [Flutter]
│
└─▶ MockFolder: Flutter
    ├─ name: "Flutter"
    ├─ level: 1
    ├─ parent: Tech  ◀── Riferimento al parent
    ├─ children: [Tips]
    │
    └─▶ MockFolder: Tips
        ├─ name: "Tips"
        ├─ level: 2
        ├─ parent: Flutter  ◀── Riferimento al parent
        └─ children: []
```

---

## 🔄 Flusso Sincronizzazione Database → UI

```
┌─────────────────────────────────────────────────────────────┐
│ STEP 1: Carica cartelle dal database                        │
│                                                              │
│  Firestore Query:                                           │
│    users/{uid}/folders/*.orderBy('createdAt')               │
│                                                              │
│  Risultato: List<Folder> (piatta)                           │
│    [                                                         │
│      { id: "abc123", name: "Tech", parentId: null },        │
│      { id: "def456", name: "Flutter", parentId: "abc123" }, │
│      { id: "ghi789", name: "Tips", parentId: "def456" }     │
│    ]                                                         │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 2: Separa root e child folders                         │
│                                                              │
│  rootFolders = folders.where(f => f.parentId == null)       │
│    ↳ [Tech]                                                 │
│                                                              │
│  childFolders = folders.where(f => f.parentId != null)      │
│    ↳ [Flutter, Tips]                                        │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 3: Crea MockFolder per tutte le root                   │
│                                                              │
│  Map<String, MockFolder> idToMockFolder = {}                │
│                                                              │
│  Per ogni rootFolder:                                        │
│    mockFolder = MockFolder(                                 │
│      name: rootFolder.name,                                 │
│      level: 0,                                              │
│      parent: null,                                          │
│      children: []                                           │
│    )                                                         │
│    idToMockFolder[rootFolder.id] = mockFolder               │
│                                                              │
│  Risultato:                                                  │
│    idToMockFolder = {                                       │
│      "abc123": MockFolder(Tech)                             │
│    }                                                         │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 4: Crea MockFolder per i child (iterativo)             │
│                                                              │
│  Iteration 1:                                                │
│    ┌─ Flutter (parentId: abc123)                            │
│    │  Parent "abc123" trovato in map? ✅                     │
│    │  ↳ Crea MockFolder:                                    │
│    │      name: "Flutter"                                   │
│    │      level: Tech.level + 1 = 1                         │
│    │      parent: Tech                                      │
│    │  ↳ Aggiungi a Tech.children                            │
│    │  ↳ idToMockFolder["def456"] = Flutter                  │
│    │                                                         │
│    └─ Tips (parentId: def456)                               │
│       Parent "def456" trovato in map? ❌ Salta             │
│                                                              │
│  Iteration 2:                                                │
│    ┌─ Tips (parentId: def456)                               │
│    │  Parent "def456" trovato in map? ✅                     │
│    │  ↳ Crea MockFolder:                                    │
│    │      name: "Tips"                                      │
│    │      level: Flutter.level + 1 = 2                      │
│    │      parent: Flutter                                   │
│    │  ↳ Aggiungi a Flutter.children                         │
│    └  ↳ idToMockFolder["ghi789"] = Tips                     │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 5: Risultato finale                                    │
│                                                              │
│  List<MockFolder> uiFolders = [                             │
│    Tutti (special),                                         │
│    Tech {                                                    │
│      children: [                                            │
│        Flutter {                                            │
│          children: [Tips]                                   │
│        }                                                     │
│      ]                                                       │
│    }                                                         │
│  ]                                                           │
│                                                              │
│  ✅ Pronto per rendering UI!                                │
└─────────────────────────────────────────────────────────────┘
```

---

## 🖼️ Flusso Generazione Anteprima

```
┌─────────────────────────────────────────────────────────────┐
│ INPUT: MockFolder folder, List<MockPost> allPosts           │
│        maxImages: 4                                          │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 1: Identifica tipo cartella                            │
│                                                              │
│  folder.isSpecial? (Cartella "Tutti")                       │
│    ✅ SI → Prendi tutti i post con immagini                 │
│    ❌ NO → Vai allo Step 2                                  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 2: Raccogli post ricorsivamente                        │
│                                                              │
│  Function: _collectPostsRecursively(folder)                 │
│                                                              │
│    1. Post diretti di folder:                               │
│       postsWithImages.addAll(                               │
│         allPosts.where(post =>                              │
│           post.sourceFolder == folder &&                    │
│           post.imageUrl != null                             │
│         )                                                    │
│       )                                                      │
│                                                              │
│    2. Ricorsione sui children:                              │
│       for (child in folder.children) {                      │
│         _collectPostsRecursively(child)  ← Ricorsivo        │
│       }                                                      │
│                                                              │
│  Esempio con Tech › Flutter › Tips:                         │
│    ┌─ Tech                                                   │
│    │  ├─ Post diretti: [post1, post2]                       │
│    │  └─ Flutter                                            │
│    │     ├─ Post diretti: [post3]                           │
│    │     └─ Tips                                            │
│    │        └─ Post diretti: [post4, post5]                 │
│    │                                                         │
│    └─ Risultato: [post1, post2, post3, post4, post5]        │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 3: Ordina per data (più recenti prima)                 │
│                                                              │
│  postsWithImages.sort(                                      │
│    (a, b) => b.savedDate.compareTo(a.savedDate)            │
│  )                                                           │
│                                                              │
│  Prima:  [post1(Jan), post2(Mar), post3(Feb), ...]          │
│  Dopo:   [post2(Mar), post3(Feb), post1(Jan), ...]          │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 4: Prendi i primi N e estrai URL                       │
│                                                              │
│  imageUrls = postsWithImages                                │
│      .take(4)                                               │
│      .map(post => post.imageUrl!)                           │
│      .toList()                                              │
│                                                              │
│  Risultato: ["url1", "url2", "url3", "url4"]                │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 5: Crea FolderPreviewStats                             │
│                                                              │
│  return FolderPreviewStats(                                 │
│    totalImagesAvailable: 15,                                │
│    recentImagesCount: 4,                                    │
│    imageUrls: ["url1", "url2", "url3", "url4"],            │
│    hasEnoughForGrid: true  // >= 2 immagini                │
│  )                                                           │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ RENDERING UI: _PostImagesGrid                               │
│                                                              │
│  switch (imageUrls.length) {                                │
│    case 1: _buildSingleImage()                             │
│    case 2: _buildTwoImages()                               │
│    case 3: _buildThreeImages()                             │
│    default: _buildFourImages()                             │
│  }                                                           │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔨 Flusso Creazione Gerarchia da Path

```
INPUT: "Tech › Flutter › Tips"

┌─────────────────────────────────────────────────────────────┐
│ STEP 1: Parse path                                          │
│                                                              │
│  fullPath = "Tech › Flutter › Tips"                         │
│  pathParts = ["Tech", "Flutter", "Tips"]                    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 2: Inizializza tracking                                │
│                                                              │
│  currentParentId = null     // Partenza da root             │
│  currentFolderId = null                                     │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ ITERATION 1: "Tech" (ROOT)                                  │
│                                                              │
│  1. Invalida cache + Reload                                 │
│     DataService.invalidateCache()                           │
│     DataService.reloadFromDisk()                            │
│                                                              │
│  2. Carica folders dal database                             │
│     realFolders = await DataService.getFolders()            │
│                                                              │
│  3. Cerca se "Tech" esiste (parentId == null)               │
│     found = realFolders.firstWhere(                         │
│       f => f.name == "Tech" && f.parentId == null           │
│     )                                                        │
│                                                              │
│     ❌ NON TROVATO                                          │
│                                                              │
│  4. Crea cartella root                                      │
│     await _createRootFolder("Tech")                         │
│       ↳ Firestore: folders.add({                            │
│            name: "Tech",                                    │
│            parentId: null,                                  │
│            ...                                              │
│          })                                                  │
│       ↳ Generato ID: "abc123"                               │
│                                                              │
│  5. Attendi propagazione (500ms)                            │
│                                                              │
│  6. Trova ID della cartella creata                          │
│     currentFolderId = "abc123"                              │
│     currentParentId = "abc123"  ← Diventa parent per next   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ ITERATION 2: "Flutter" (CHILD)                              │
│                                                              │
│  1. Invalida cache + Reload                                 │
│                                                              │
│  2. Carica folders aggiornate                               │
│                                                              │
│  3. Cerca se "Flutter" esiste (parentId == "abc123")        │
│     found = realFolders.firstWhere(                         │
│       f => f.name == "Flutter" && f.parentId == "abc123"    │
│     )                                                        │
│                                                              │
│     ❌ NON TROVATO                                          │
│                                                              │
│  4. Crea sottocartella                                      │
│     await _createChildFolder("abc123", "Flutter")           │
│       ↳ Firestore: folders.add({                            │
│            name: "Flutter",                                 │
│            parentId: "abc123",  ← Riferimento a Tech        │
│            ...                                              │
│          })                                                  │
│       ↳ Generato ID: "def456"                               │
│                                                              │
│  5. Attendi propagazione                                    │
│                                                              │
│  6. Trova ID                                                │
│     currentFolderId = "def456"                              │
│     currentParentId = "def456"  ← Diventa parent per next   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ ITERATION 3: "Tips" (CHILD)                                 │
│                                                              │
│  1. Invalida cache + Reload                                 │
│                                                              │
│  2. Carica folders aggiornate                               │
│                                                              │
│  3. Cerca se "Tips" esiste (parentId == "def456")           │
│     found = realFolders.firstWhere(                         │
│       f => f.name == "Tips" && f.parentId == "def456"       │
│     )                                                        │
│                                                              │
│     ❌ NON TROVATO                                          │
│                                                              │
│  4. Crea sottocartella                                      │
│     await _createChildFolder("def456", "Tips")              │
│       ↳ Firestore: folders.add({                            │
│            name: "Tips",                                    │
│            parentId: "def456",  ← Riferimento a Flutter     │
│            ...                                              │
│          })                                                  │
│       ↳ Generato ID: "ghi789"                               │
│                                                              │
│  5. Attendi propagazione                                    │
│                                                              │
│  6. Trova ID                                                │
│     currentFolderId = "ghi789"                              │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ RISULTATO FINALE                                             │
│                                                              │
│  return "ghi789"  // ID di "Tips"                           │
│                                                              │
│  Database Firestore:                                         │
│    ┌─ abc123: Tech (parentId: null)                         │
│    ├─ def456: Flutter (parentId: abc123)                    │
│    └─ ghi789: Tips (parentId: def456)                       │
│                                                              │
│  ✅ Gerarchia completa creata!                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 📱 Rendering Widget Anteprime

### Layout 1 Immagine

```
╔═══════════════════════════════════╗
║                                   ║
║                                   ║
║           [Immagine]              ║
║                                   ║
║                                   ║
╚═══════════════════════════════════╝
```

### Layout 2 Immagini

```
╔═══════════════════════════════════╗
║                                   ║
║         [Immagine 1]              ║
║                                   ║
╠═══════════════════════════════════╣
║                                   ║
║         [Immagine 2]              ║
║                                   ║
╚═══════════════════════════════════╝
```

### Layout 3 Immagini

```
╔═════════════════╦═════════════════╗
║                 ║                 ║
║  [Immagine 1]   ║  [Immagine 2]   ║
║                 ║                 ║
╠═════════════════╩═════════════════╣
║                                   ║
║         [Immagine 3]              ║
║                                   ║
╚═══════════════════════════════════╝
```

### Layout 4+ Immagini

```
╔═════════════════╦═════════════════╗
║                 ║                 ║
║  [Immagine 1]   ║  [Immagine 2]   ║
║                 ║                 ║
╠═════════════════╬═════════════════╣
║                 ║                 ║
║  [Immagine 3]   ║  [Immagine 4]   ║
║                 ║                 ║
╚═════════════════╩═════════════════╝
```

---

## 🔍 Ricerca Cartella Database da MockFolder

```
INPUT: 
  - dbFolders: Lista flat di Folder
  - mockFolder: Tips (UI)

┌─────────────────────────────────────────────────────────────┐
│ STEP 1: Costruisci path dalla MockFolder                    │
│                                                              │
│  MockFolder: Tips                                            │
│    ↑                                                         │
│  parent: Flutter                                            │
│    ↑                                                         │
│  parent: Tech                                               │
│    ↑                                                         │
│  parent: null                                               │
│                                                              │
│  mockPath = ["Tech", "Flutter", "Tips"]                     │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 2: Cerca "Tech" (root)                                 │
│                                                              │
│  found = dbFolders.firstWhere(                              │
│    f => f.name == "Tech" &&                                 │
│         f.parentId == null &&                               │
│         !f.isDefault                                        │
│  )                                                           │
│                                                              │
│  ✅ TROVATO: { id: "abc123", name: "Tech" }                │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 3: Cerca "Flutter" (child di Tech)                     │
│                                                              │
│  previousId = "abc123"                                      │
│                                                              │
│  found = dbFolders.firstWhere(                              │
│    f => f.name == "Flutter" &&                              │
│         f.parentId == "abc123"                              │
│  )                                                           │
│                                                              │
│  ✅ TROVATO: { id: "def456", name: "Flutter" }             │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 4: Cerca "Tips" (child di Flutter)                     │
│                                                              │
│  previousId = "def456"                                      │
│                                                              │
│  found = dbFolders.firstWhere(                              │
│    f => f.name == "Tips" &&                                 │
│         f.parentId == "def456"                              │
│  )                                                           │
│                                                              │
│  ✅ TROVATO: { id: "ghi789", name: "Tips" }                │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ RISULTATO                                                    │
│                                                              │
│  return Folder(                                             │
│    id: "ghi789",                                            │
│    name: "Tips",                                            │
│    parentId: "def456"                                       │
│  )                                                           │
│                                                              │
│  ✅ Folder database trovata!                                │
└─────────────────────────────────────────────────────────────┘
```

---

## 📦 Salvataggio Post in Cartella

```
INPUT: URL, Title, FolderId

┌─────────────────────────────────────────────────────────────┐
│ STEP 1: Utente salva post in "Tech › Flutter › Tips"        │
│                                                              │
│  User Interface:                                             │
│    [SavePostDialog]                                         │
│      ↓                                                       │
│    selectedFolder = Tips (MockFolder)                       │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 2: Trova ID database della cartella                    │
│                                                              │
│  dbFolders = await DataService.getFolders()                 │
│                                                              │
│  dbFolder = FolderSynchronizationManager                    │
│      .findDatabaseFolderFromMock(dbFolders, Tips)           │
│                                                              │
│  Result: { id: "ghi789", name: "Tips" }                     │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 3: Crea e salva post                                   │
│                                                              │
│  post = await PostManagement.savePostToFolder(              │
│    url: "https://flutter.dev/docs",                         │
│    title: "Flutter Best Practices",                         │
│    imageUrl: "https://flutter.dev/image.jpg",               │
│    folderId: "ghi789"  ← Collegato a Tips                   │
│  )                                                           │
│                                                              │
│  Firestore:                                                  │
│    users/{uid}/posts/{postId} = {                           │
│      url: "...",                                            │
│      title: "...",                                          │
│      imageUrl: "...",                                       │
│      folderId: "ghi789",  ← Link alla cartella              │
│      createdAt: Timestamp                                   │
│    }                                                         │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 4: Sincronizzazione UI                                 │
│                                                              │
│  1. Ricarica post da database                               │
│     dbPosts = await DataService.getPosts()                  │
│                                                              │
│  2. Sincronizza post                                        │
│     uiPosts = await PostManagement                          │
│         .syncPostsFromDatabase(dbPosts, dbFolders, ...)     │
│                                                              │
│  3. Post collegato a MockFolder Tips                        │
│     MockPost {                                              │
│       title: "Flutter Best Practices",                      │
│       imageUrl: "...",                                      │
│       sourceFolder: Tips (MockFolder)  ← Collegato          │
│     }                                                        │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 5: Anteprima aggiornata automaticamente                │
│                                                              │
│  FolderCard per Tips:                                       │
│    ↓                                                         │
│  getFolderPreviewImages(Tips)                               │
│    ↓                                                         │
│  Trova post in Tips ricorsivamente                          │
│    ↳ [Flutter Best Practices]                               │
│    ↓                                                         │
│  Estrai imageUrl                                            │
│    ↳ ["https://flutter.dev/image.jpg"]                      │
│    ↓                                                         │
│  Mostra in _PostImagesGrid                                  │
│                                                              │
│  ✅ Anteprima visualizzata!                                 │
└─────────────────────────────────────────────────────────────┘
```

---

**Diagrammi creati**: Dicembre 2025
**Per**: Sistema gestione cartelle SaveIt App



