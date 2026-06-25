const admin = require("firebase-admin");

const PROJECT_ID = "saveit-app-1784d";

admin.initializeApp({projectId: PROJECT_ID});

const db = admin.firestore();

const args = Object.fromEntries(
  process.argv.slice(2).map((arg) => {
    const [key, ...rest] = arg.replace(/^--/, "").split("=");
    return [key, rest.join("=") || "true"];
  })
);

const dryRun = args.delete !== "true";
const onlyUid = (args.uid || "").toString().trim();
const limit = Number(args.limit || 0);

const normalizeId = (value) => (value || "").toString().trim();

const deleteDocs = async (docs, label) => {
  if (docs.length === 0) return 0;

  if (dryRun) {
    console.log(`Would delete ${docs.length} ${label}`);
    return docs.length;
  }

  let deleted = 0;
  for (let i = 0; i < docs.length; i += 450) {
    const batch = db.batch();
    const chunk = docs.slice(i, i + 450);
    chunk.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    deleted += chunk.length;
  }
  console.log(`Deleted ${deleted} ${label}`);
  return deleted;
};

const orphanFolderIdsForUser = (folders) => {
  const folderIds = new Set(folders.map((folder) => folder.id));
  const orphanIds = new Set();

  let changed = true;
  while (changed) {
    changed = false;
    for (const folder of folders) {
      if (orphanIds.has(folder.id)) continue;
      const data = folder.data || {};
      if (data.isDefault === true) continue;

      const parentId = normalizeId(data.parentId);
      const parentMissing = parentId && !folderIds.has(parentId);
      const parentIsOrphan = parentId && orphanIds.has(parentId);

      if (parentMissing || parentIsOrphan) {
        orphanIds.add(folder.id);
        changed = true;
      }
    }
  }

  return orphanIds;
};

const cleanupUserContent = async (userDoc) => {
  const userRef = userDoc.ref;
  const [foldersSnapshot, postsSnapshot] = await Promise.all([
    userRef.collection("folders").get(),
    userRef.collection("posts").get(),
  ]);

  const folders = foldersSnapshot.docs.map((doc) => ({
    id: doc.id,
    ref: doc.ref,
    data: doc.data() || {},
  }));
  const posts = postsSnapshot.docs.map((doc) => ({
    id: doc.id,
    ref: doc.ref,
    data: doc.data() || {},
  }));

  const folderIds = new Set(folders.map((folder) => folder.id));
  const orphanFolderIds = orphanFolderIdsForUser(folders);

  const orphanFolders = folders.filter((folder) => orphanFolderIds.has(folder.id));
  const orphanPosts = posts.filter((post) => {
    const folderId = normalizeId(post.data.folderId);
    return !folderId || !folderIds.has(folderId) || orphanFolderIds.has(folderId);
  });

  if (orphanFolders.length === 0 && orphanPosts.length === 0) {
    return {
      userId: userDoc.id,
      folders: folders.length,
      posts: posts.length,
      orphanFolders: 0,
      orphanPosts: 0,
    };
  }

  console.log(`\nUser ${userDoc.id}`);
  console.log(`Folders: ${folders.length}, posts: ${posts.length}`);
  console.log(`Orphan folders: ${orphanFolders.length}`);
  orphanFolders.slice(0, 20).forEach((folder) => {
    console.log(`  folder ${folder.id} "${folder.data.name || ""}" parentId=${normalizeId(folder.data.parentId)}`);
  });
  if (orphanFolders.length > 20) {
    console.log(`  ...and ${orphanFolders.length - 20} more orphan folders`);
  }
  console.log(`Orphan posts: ${orphanPosts.length}`);
  orphanPosts.slice(0, 20).forEach((post) => {
    console.log(`  post ${post.id} "${post.data.title || ""}" folderId=${normalizeId(post.data.folderId)}`);
  });
  if (orphanPosts.length > 20) {
    console.log(`  ...and ${orphanPosts.length - 20} more orphan posts`);
  }

  const deletedPosts = await deleteDocs(orphanPosts, "orphan posts");
  const deletedFolders = await deleteDocs(orphanFolders, "orphan folders");

  return {
    userId: userDoc.id,
    folders: folders.length,
    posts: posts.length,
    orphanFolders: orphanFolders.length,
    orphanPosts: orphanPosts.length,
    deletedFolders,
    deletedPosts,
  };
};

const main = async () => {
  console.log(`Running orphan content cleanup in ${dryRun ? "DRY-RUN" : "DELETE"} mode`);

  const usersSnapshot = onlyUid
    ? await db.collection("users").where(admin.firestore.FieldPath.documentId(), "==", onlyUid).get()
    : await db.collection("users").get();

  const results = [];
  for (const userDoc of usersSnapshot.docs) {
    if (limit > 0 && results.length >= limit) break;
    results.push(await cleanupUserContent(userDoc));
  }

  const totals = results.reduce(
    (acc, result) => ({
      scannedUsers: acc.scannedUsers + 1,
      folders: acc.folders + result.folders,
      posts: acc.posts + result.posts,
      orphanFolders: acc.orphanFolders + result.orphanFolders,
      orphanPosts: acc.orphanPosts + result.orphanPosts,
      deletedFolders: acc.deletedFolders + (result.deletedFolders || 0),
      deletedPosts: acc.deletedPosts + (result.deletedPosts || 0),
    }),
    {
      scannedUsers: 0,
      folders: 0,
      posts: 0,
      orphanFolders: 0,
      orphanPosts: 0,
      deletedFolders: 0,
      deletedPosts: 0,
    }
  );

  console.log("\nSummary:");
  console.log(JSON.stringify({
    mode: dryRun ? "dry-run" : "delete",
    ...totals,
  }, null, 2));
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Cleanup failed:", error);
    process.exit(1);
  });
