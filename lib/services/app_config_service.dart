import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class VersionControlConfig {
  final bool maintenance;
  final String message;
  final int minBuildAndroid;
  final int minBuildIos;
  final String androidStoreUrl;
  final String iosStoreUrl;

  const VersionControlConfig({
    this.maintenance = false,
    this.message = '',
    this.minBuildAndroid = 0,
    this.minBuildIos = 0,
    this.androidStoreUrl =
        'https://play.google.com/store/apps/details?id=eu.savein.app',
    this.iosStoreUrl = '',
  });

  factory VersionControlConfig.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const VersionControlConfig();

    int readInt(dynamic value, {int fallback = 0}) {
      if (value == null) return fallback;
      return int.tryParse(value.toString()) ?? fallback;
    }

    final legacyMinBuild = readInt(data['minBuild']);
    final minAndroid = readInt(
      data['minBuildAndroid'],
      fallback: legacyMinBuild,
    );
    final minIos = readInt(
      data['minBuildIos'],
      fallback: legacyMinBuild,
    );

    return VersionControlConfig(
      maintenance: data['maintenance'] == true,
      message: (data['message'] ?? '').toString().trim(),
      minBuildAndroid: minAndroid,
      minBuildIos: minIos,
      androidStoreUrl: (data['androidStoreUrl'] ??
              'https://play.google.com/store/apps/details?id=eu.savein.app')
          .toString()
          .trim(),
      iosStoreUrl: (data['iosStoreUrl'] ?? '').toString().trim(),
    );
  }

  int minBuildForCurrentPlatform() {
    if (kIsWeb) return 0;
    if (!kIsWeb && Platform.isIOS) return minBuildIos;
    if (!kIsWeb && Platform.isAndroid) return minBuildAndroid;
    return 0;
  }

  String storeUrlForCurrentPlatform() {
    if (!kIsWeb && Platform.isIOS && iosStoreUrl.isNotEmpty) {
      return iosStoreUrl;
    }
    return androidStoreUrl;
  }
}

class AppConfigService {
  AppConfigService._();

  static const _docPath = 'app_config/version_control';

  /// Fail-open se Firestore non risponde: non blocca per errori di rete.
  static Future<VersionControlConfig> fetch() async {
    if (kIsWeb) return const VersionControlConfig();

    try {
      final doc = await FirebaseFirestore.instance
          .doc(_docPath)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
      if (!doc.exists) return const VersionControlConfig();
      return VersionControlConfig.fromMap(doc.data());
    } catch (_) {
      return const VersionControlConfig();
    }
  }

  static Future<int> currentBuildNumber() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }
}
