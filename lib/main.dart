import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:klang_universum/core/services/audio_service.dart';
import 'package:klang_universum/core/services/progress_service.dart';
import 'package:klang_universum/core/services/settings_service.dart';
import 'package:klang_universum/core/services/sri_service.dart';
import 'package:klang_universum/features/games/game_registry.dart';
import 'package:klang_universum/features/games/songs/user_songs_service.dart';
import 'package:klang_universum/features/home/screens/home_screen.dart';
import 'package:klang_universum/l10n/app_localizations.dart';
import 'package:klang_universum/shared/theme.dart';
import 'package:partitura/partitura.dart' show Bravura;
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Per the partitura contract (CONTRACT.md §6): await the SMuFL metadata
  // up front so the first StaffView frame is never empty.
  await Bravura.load();
  runApp(const KlangUniversumApp());
}

class KlangUniversumApp extends StatelessWidget {
  const KlangUniversumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SriService()..loadSriData(),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsService()..load(),
        ),
        Provider<AudioService>(
          create: (_) => AudioService(),
          dispose: (_, service) => service.dispose(),
        ),
        ChangeNotifierProvider(
          create: (_) => ProgressService()..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => UserSongsService()..load(),
        ),
      ],
      child: Consumer<SettingsService>(
        builder: (context, settings, _) => MaterialApp(
          onGenerateTitle: (context) =>
              AppLocalizations.of(context)?.appTitle ?? 'KlangUniversum',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: settings.locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('de')],
          home: const _StartupRouter(),
        ),
      ),
    );
  }
}

/// Shows the home screen; on web, a `?game=<gameId>` query parameter opens
/// that game directly — deep links for testing and sharing.
class _StartupRouter extends StatefulWidget {
  const _StartupRouter();

  @override
  State<_StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends State<_StartupRouter> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final gameId = Uri.base.queryParameters['game'];
      if (gameId == null || !mounted) return;
      for (final games in kGamesByModule.values) {
        for (final game in games) {
          if (game.id == gameId) {
            Navigator.of(context)
                .push(MaterialPageRoute(builder: game.builder));
            return;
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => const HomeScreen();
}
