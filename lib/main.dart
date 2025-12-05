import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'pages/dashboard_page.dart';
import 'pages/history_page.dart';

// --- API KEY ---
// ⚠️ PENTING: Jangan upload API Key ini ke GitHub publik untuk keamanan saldo
const String geminiApiKey = 'AIzaSyAlU7u6PVkwWu-gImRaVyphTvgjY718Wnc';

// Global Notifier untuk Tema (exported untuk digunakan di halaman lain)
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inisialisasi Firebase dengan konfigurasi otomatis dari firebase_options.dart
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'IoT Dapur AI',
          themeMode: mode,
          // TEMA TERANG
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF4C7CF6),
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xFFF5F6FA),
            textTheme: GoogleFonts.outfitTextTheme(), // Font Otomatis
          ),
          // TEMA GELAP
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF4C7CF6),
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF121212),
            textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
          ),
          home: const HomePage(),
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  final List<Widget> _pages = [const DashboardTab(), const HistoryPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _pages[_selectedIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard AI',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.settings_remote_outlined,
            ), // Icon diganti agar relevan
            selectedIcon: Icon(Icons.settings_remote),
            label: 'Kontrol & Log',
          ),
        ],
      ),
    );
  }
}

