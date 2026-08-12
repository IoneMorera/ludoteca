import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'config/api_config.dart';
import 'data/sync_service.dart';
import 'providers/auth_provider.dart';
import 'providers/bgg_collection_provider.dart';
import 'providers/juegos_provider.dart';
import 'providers/sync_provider.dart';
import 'screens/bgg_screen.dart';
import 'screens/categorias_screen.dart';
import 'screens/colecciones_screen.dart';
import 'screens/fundas_faltantes_screen.dart';
import 'screens/game_night_screen.dart';
import 'screens/home_screen.dart';
import 'screens/juego_detail_screen.dart';
import 'screens/juego_form_screen.dart';
import 'screens/juegos_aviso_screen.dart';
import 'screens/juegos_list_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/propietarios_screen.dart';
import 'screens/recognize_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tipos_funda_screen.dart';
import 'screens/ubicaciones_screen.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await ApiConfig.init();
  ApiService().updateBaseUrl(ApiConfig.serverUrl);
  runApp(const LudotecaApp());
}

class LudotecaApp extends StatelessWidget {
  const LudotecaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => JuegosProvider()),
        ChangeNotifierProvider(create: (_) => SyncProvider()),
        ChangeNotifierProvider(create: (_) => BggCollectionProvider()),
      ],
      child: MaterialApp(
        title: 'Ludoteca',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('es', 'ES'),
          Locale('en', 'US'),
        ],
        locale: const Locale('es', 'ES'),
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF1E3A5F),
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF1E3A5F),
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        home: const AuthGate(),
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case '/login':
              return MaterialPageRoute(builder: (_) => const LoginScreen());
            case '/home':
              return MaterialPageRoute(builder: (_) => const MainShell());
            case '/juego':
              final args = settings.arguments;
              if (args is int) {
                return MaterialPageRoute(
                    builder: (_) => JuegoDetailScreen(juegoLocalId: args));
              }
              if (args is Map<String, dynamic>) {
                return MaterialPageRoute(
                    builder: (_) => JuegoDetailScreen(
                          juegoLocalId: args['local_id'] as int?,
                          juegoServerId: args['server_id'] as int?,
                        ));
              }
              return MaterialPageRoute(builder: (_) => const MainShell());
            case '/juegos':
              final args = settings.arguments as Map<String, dynamic>?;
              return MaterialPageRoute(
                  builder: (_) => JuegosListScreen(
                        initialEstado: args?['estado'] as String?,
                        initialEsExpansion: args?['esExpansion'] as bool?,
                        categoriaLocalId: args?['categoriaLocalId'] as int?,
                        tipoFundaLocalId: args?['tipoFundaLocalId'] as int?,
                        ubicacionLocalId: args?['ubicacionLocalId'] as int?,
                      ));
            case '/juego/nuevo':
              final prefill = settings.arguments as Map<String, dynamic>?;
              return MaterialPageRoute(
                  builder: (_) => JuegoFormScreen(bggPrefill: prefill));
            case '/juego/editar':
              final localId = settings.arguments as int;
              return MaterialPageRoute(
                  builder: (_) => JuegoFormScreen(juegoLocalId: localId));
            case '/game-night':
              return MaterialPageRoute(
                  builder: (_) => const GameNightScreen());
            case '/recognize':
              return MaterialPageRoute(
                  builder: (_) => const RecognizeScreen());
            case '/colecciones':
              return MaterialPageRoute(
                  builder: (_) => const ColeccionesScreen());
            case '/fundas-faltantes':
              return MaterialPageRoute(
                  builder: (_) => const FundasFaltantesScreen());
            case '/juegos-por-estrenar':
              return MaterialPageRoute(
                  builder: (_) => const JuegosAvisoScreen(
                      tipo: JuegoAvisoTipo.porEstrenar));
            case '/faltan-traducciones':
              return MaterialPageRoute(
                  builder: (_) => const JuegosAvisoScreen(
                      tipo: JuegoAvisoTipo.faltanTraduccion));
            case '/expansiones-otro-idioma':
              return MaterialPageRoute(
                  builder: (_) => const JuegosAvisoScreen(
                      tipo: JuegoAvisoTipo.expansionOtroIdioma));
            case '/juegos-por-colocar':
              return MaterialPageRoute(
                  builder: (_) => const JuegosAvisoScreen(
                      tipo: JuegoAvisoTipo.porColocar));
            case '/tipos-funda':
              return MaterialPageRoute(
                  builder: (_) => const TiposFundaScreen());
            case '/ubicaciones':
              return MaterialPageRoute(
                  builder: (_) => const UbicacionesScreen());
            case '/categorias':
              return MaterialPageRoute(
                  builder: (_) => const CategoriasScreen());
            case '/propietarios':
              return MaterialPageRoute(
                  builder: (_) => const PropietariosScreen());
            case '/bgg':
              return MaterialPageRoute(builder: (_) => const BggScreen());
            case '/profile':
              return MaterialPageRoute(builder: (_) => const ProfileScreen());
            default:
              return MaterialPageRoute(builder: (_) => const MainShell());
          }
        },
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final auth = context.read<AuthProvider>();
    final loggedIn = await auth.checkAuth();

    if (loggedIn) {
      // Sincronizaci\u00f3n inicial: full pull si nunca se ha sincronizado.
      SyncService().syncAll();
      if (auth.bggConnected) {
        // ignore: unawaited_futures
        context.read<BggCollectionProvider>().fetchOwnedIds();
      }
    }

    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final auth = context.watch<AuthProvider>();
    return auth.isAuthenticated ? const MainShell() : const LoginScreen();
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  late final List<Widget> _screens = [
    const HomeScreen(),
    JuegosListScreen(onBack: () => setState(() => _currentIndex = 0)),
    const SizedBox(),
    const ColeccionesScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          if (index == 2) {
            Navigator.of(context).pushNamed('/recognize');
            return;
          }
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.casino_outlined),
            selectedIcon: Icon(Icons.casino),
            label: 'Juegos',
          ),
          NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt),
            label: 'Reconocer',
          ),
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark),
            label: 'Colecciones',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Más',
          ),
        ],
      ),
    );
  }
}
