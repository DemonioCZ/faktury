import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'services/settings.dart';
import 'services/updater.dart';
import 'ui/home.dart';
import 'ui/setup_pages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Aplikace kreslí až k okraji displeje, systémová lišta dole je průhledná
  // a obsah se odsazuje, aby do ní nezajížděl.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await initializeDateFormatting('cs');
  final settings = await Settings.load();
  final state = AppState(settings);
  runApp(ChangeNotifierProvider.value(value: state, child: const FakturyApp()));
  state.init();
  Updater().cleanup();
}

const seed = Color(0xFF1F6F5C);

ThemeData _theme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: b);
  final dark = b == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(
      surface: dark ? const Color(0xFF141514) : const Color(0xFFF4F2EE),
      surfaceContainerLow: dark ? const Color(0xFF1D1F1E) : Colors.white,
      surfaceContainerHighest: dark ? const Color(0xFF2A2D2B) : const Color(0xFFEFECE6),
    ),
    scaffoldBackgroundColor: dark ? const Color(0xFF141514) : const Color(0xFFF4F2EE),
    visualDensity: VisualDensity.standard,
    chipTheme: const ChipThemeData(showCheckmark: false),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

class FakturyApp extends StatelessWidget {
  const FakturyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Faktury',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      locale: const Locale('cs'),
      supportedLocales: const [Locale('cs'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Root(),
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
            systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          ),
          child: child!,
        );
      },
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (!s.signedIn) return const SignInPage();
    if (!s.configured) return const FolderPickerPage();
    return const HomePage();
  }
}
