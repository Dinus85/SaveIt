const admin = require("firebase-admin");
admin.initializeApp();

const db = admin.firestore();

const seed = async () => {
  const rules = {
    "root_folders": {
      "free": {enabled: true, limit: 10, period: "total", requiresAd: false},
      "premium": {enabled: true, limit: 0, period: "total", requiresAd: false},
    },
    "child_folders": {
      "free": {enabled: true, limit: 4, period: "total", requiresAd: false},
      "premium": {enabled: true, limit: 0, period: "total", requiresAd: false},
    },
    "folder_levels": {
      "free": {enabled: true, limit: 1, period: "total", requiresAd: false},
      "premium": {enabled: true, limit: 0, period: "total", requiresAd: false},
    },
    "manual_tags": {
      "free": {enabled: false, limit: 0, period: "total", requiresAd: false},
      "premium": {enabled: true, limit: 0, period: "total", requiresAd: false},
    },
    "share_folder": {
      "free": {enabled: true, limit: 1, period: "day", requiresAd: true},
      "premium": {enabled: true, limit: 0, period: "day", requiresAd: false},
    },
    "share_post": {
      "free": {enabled: true, limit: 3, period: "day", requiresAd: true},
      "premium": {enabled: true, limit: 0, period: "day", requiresAd: false},
    },
    "import_shared": {
      "free": {enabled: true, limit: 5, period: "day", requiresAd: true},
      "premium": {enabled: true, limit: 0, period: "day", requiresAd: false},
    },
  };

  console.log("Seeding plan limits...");
  await db.doc("config/plan_limits").set({
    featureRules: rules,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: "system-seed",
  }, {merge: true});
  console.log("Done!");
};

seed().then(() => process.exit(0)).catch(err => {
  console.error(err);
  process.exit(1);
});
