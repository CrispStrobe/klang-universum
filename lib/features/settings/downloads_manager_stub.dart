// Web stub — no local download cache on web.
import 'package:comet_beat/features/settings/downloads_manager_types.dart';

bool get downloadsSupported => false;
Future<List<DownloadCategory>> scanDownloads({String? rootOverride}) async =>
    const [];
Future<void> clearDownloads(String path) async {}
