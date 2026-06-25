const admin = require("firebase-admin");

admin.initializeApp({projectId: "saveit-app-1784d"});
const db = admin.firestore();

const args = Object.fromEntries(
  process.argv.slice(2).map((arg) => {
    const [key, ...rest] = arg.replace(/^--/, "").split("=");
    return [key, rest.join("=") || "true"];
  })
);

const sourceUid = args.source;
const targetUid = args.target;
const rootFolderId = args.root;
const targetParentId = args.parent || null;
const dryRun = args["dry-run"] === "true";

if (!sourceUid || !targetUid || !rootFolderId) {
  console.error(
    "Uso: node manual_copy_folder.js --source=SOURCE_UID --target=TARGET_UID --root=ROOT_FOLDER_ID [--parent=TARGET_PARENT_ID] [--dry-run=true]"
  );
  process.exit(1);
}

const normalizeId = (value) => (value || "").toString().trim();

const serialize = (data) => {
  const out = {...data};
  for (const [key, value] of Object.entries(out)) {
    if (value && typeof value.toDate === "function") {
      out[key] = value.toDate().toISOString();
    }
  }
  return out;
};

const parseDate = (value) => {
  if (!value) return admin.firestore.FieldValue.serverTimestamp();
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? admin.firestore.FieldValue.serverTimestamp()
    : admin.firestore.Timestamp.fromDate(date);
};

const safePreviewUrl = (value) => {
  const url = (value || "").toString().trim();
  if (!url) return null;
  const lower = url.toLowerCase();
  const userScoped = lower.includes("/users/") || lower.includes("users%2f");
  return userScoped && lower.includes("post_previews") ? null : url;
};

const copyFolderData = (data, newParentId) => ({
  name: data.name || "Cartella importata",
  color: data.color || "#BB86FC",
  createdAt: parseDate(data.createdAt),
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  isDefault: false,
  parentId: newParentId || null,
  isShared: true,
  manuallyImportedFrom: sourceUid,
  manuallyImportedAt: admin.firestore.FieldValue.serverTimestamp(),
});

const copyPostData = (data, newFolderId) => ({
  url: data.url || "",
  title: data.title || "Post importato",
  description: data.description || "",
  imageUrl: data.imageUrl || null,
  previewStorageUrl: safePreviewUrl(data.previewStorageUrl),
  creatorName: data.creatorName || null,
  creatorUsername: data.creatorUsername || null,
  tags: Array.isArray(data.tags)
    ? Array.from(new Set([...data.tags.map(String), "condiviso"]))
    : ["condiviso"],
  folderId: newFolderId,
  createdAt: parseDate(data.createdAt),
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  isShared: true,
  manuallyImportedFrom: sourceUid,
  manuallyImportedAt: admin.firestore.FieldValue.serverTimestamp(),
});

async function main() {
  const sourceFoldersRef = db.collection("users").doc(sourceUid).collection("folders");
  const targetFoldersRef = db.collection("users").doc(targetUid).collection("folders");
  const sourcePostsRef = db.collection("users").doc(sourceUid).collection("posts");
  const targetPostsRef = db.collection("users").doc(targetUid).collection("posts");

  const rootDoc = await sourceFoldersRef.doc(rootFolderId).get();
  if (!rootDoc.exists) {
    throw new Error(`Cartella root non trovata: ${rootFolderId}`);
  }

  if (targetParentId) {
    const targetParentDoc = await targetFoldersRef.doc(targetParentId).get();
    if (!targetParentDoc.exists) {
      throw new Error(`Parent target non trovato: ${targetParentId}`);
    }
  }

  const folderSnap = await sourceFoldersRef.get();
  const folders = folderSnap.docs.map((doc) => ({
    id: doc.id,
    data: serialize(doc.data() || {}),
  }));

  const includedIds = new Set([rootFolderId]);
  let changed = true;
  while (changed) {
    changed = false;
    for (const folder of folders) {
      const parentId = normalizeId(folder.data.parentId);
      if (parentId && includedIds.has(parentId) && !includedIds.has(folder.id)) {
        includedIds.add(folder.id);
        changed = true;
      }
    }
  }

  const folderById = new Map(folders.map((folder) => [folder.id, folder]));
  const depthOf = (folder) => {
    let depth = 0;
    let parentId = normalizeId(folder.data.parentId);
    const seen = new Set();
    while (parentId && includedIds.has(parentId) && !seen.has(parentId)) {
      seen.add(parentId);
      depth++;
      parentId = normalizeId(folderById.get(parentId)?.data?.parentId);
    }
    return depth;
  };

  const foldersToCopy = folders
    .filter((folder) => includedIds.has(folder.id))
    .sort((a, b) => {
      if (a.id === rootFolderId) return -1;
      if (b.id === rootFolderId) return 1;
      return depthOf(a) - depthOf(b);
    });

  const postSnap = await sourcePostsRef.get();
  const postsToCopy = postSnap.docs
    .map((doc) => ({id: doc.id, data: serialize(doc.data() || {})}))
    .filter((post) => includedIds.has(normalizeId(post.data.folderId)));

  console.log(`Source: ${sourceUid}`);
  console.log(`Target: ${targetUid}`);
  console.log(`Root: ${rootFolderId} (${rootDoc.data().name || "senza nome"})`);
  console.log(`Cartelle da copiare: ${foldersToCopy.length}`);
  console.log(`Post da copiare: ${postsToCopy.length}`);

  if (dryRun) {
    console.log("DRY RUN: nessuna scrittura eseguita.");
    return;
  }

  const idMap = new Map();
  let batch = db.batch();
  let writes = 0;

  const commitIfNeeded = async () => {
    if (writes >= 450) {
      await batch.commit();
      batch = db.batch();
      writes = 0;
    }
  };

  for (const folder of foldersToCopy) {
    const oldParentId = normalizeId(folder.data.parentId);
    const newParentId =
      folder.id === rootFolderId
        ? targetParentId
        : idMap.get(oldParentId) || idMap.get(rootFolderId) || targetParentId;
    const newRef = targetFoldersRef.doc();
    idMap.set(folder.id, newRef.id);
    batch.set(newRef, copyFolderData(folder.data, newParentId));
    writes++;
    await commitIfNeeded();
  }

  for (const post of postsToCopy) {
    const mappedFolderId = idMap.get(normalizeId(post.data.folderId));
    if (!mappedFolderId) continue;
    batch.set(targetPostsRef.doc(), copyPostData(post.data, mappedFolderId));
    writes++;
    await commitIfNeeded();
  }

  if (writes > 0) await batch.commit();

  console.log(`Import completato. Nuova root: ${idMap.get(rootFolderId)}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
