import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart'; // Import Font Keren
import 'package:google_generative_ai/google_generative_ai.dart';
import 'firebase_options.dart';

// --- API KEY ---
// ⚠️ PENTING: Jangan upload API Key ini ke GitHub publik untuk keamanan saldo
const String geminiApiKey = 'AIzaSyAlU7u6PVkwWu-gImRaVyphTvgjY718Wnc';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inisialisasi Firebase dengan konfigurasi otomatis dari firebase_options.dart
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

// Global Notifier untuk Tema
final ValueNotifier<ThemeMode> _themeNotifier = ValueNotifier(ThemeMode.light);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeNotifier,
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
  final List<Widget> _pages = [const DashboardTab(), const LogsTab()];

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

// --- DASHBOARD TAB ---
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});
  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  // Data Sensor
  String suhu = "0";
  String hum = "0";
  String gas = "0";
  bool isDeviceOn = false;
  bool isConnected = false;

  // Settingan & Status
  bool fiturAlarmSuara = true;
  bool fiturNotifikasi = true;
  bool fiturSuaraRobot = true;
  double batasBahayaGas = 400.0;
  bool isDangerMode = false; // Untuk mencegah spam alarm

  // Tools
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer audioPlayer = AudioPlayer();
  final FlutterTts flutterTts = FlutterTts();
  late GenerativeModel _geminiModel;

  // Debounce Timer
  Timer? _ttsTimer;

  // Grafik
  List<FlSpot> suhuPoints = [];
  List<FlSpot> gasPoints = [];
  double xValue = 0;

  // AI State
  String aiResponse = "Klik tombol robot untuk analisis...";
  bool isAiLoading = false;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _initTts();
    _initGemini();
    _initListeners();
  }

  void _initGemini() {
    _geminiModel = GenerativeModel(model: 'gemini-pro', apiKey: geminiApiKey);
  }

  void _initTts() async {
    await flutterTts.setLanguage("id-ID");
    await flutterTts.setPitch(1.0);
  }

  void _initNotifications() async {
    const AndroidInitializationSettings initSetting =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(android: initSetting),
    );
  }

  // --- LOGIKA AI GEMINI ---
  Future<void> _askGemini() async {
    setState(() {
      isAiLoading = true;
      aiResponse = "Sedang berpikir...";
    });

    try {
      final prompt =
          '''
      Data sensor dapur: Gas $gas PPM, Suhu $suhu°C, Kelembapan $hum%.
      Analisis singkat (1 kalimat): Apakah aman?
      Saran (1 kalimat): Apa yang harus dilakukan?
      Jawab dengan gaya asisten pintar.
      ''';

      final content = [Content.text(prompt)];
      final response = await _geminiModel.generateContent(content);

      if (mounted) {
        setState(() {
          aiResponse = response.text ?? "AI tidak merespon.";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => aiResponse = "Gagal koneksi AI. Cek internet.");
      }
    } finally {
      if (mounted) {
        setState(() => isAiLoading = false);
      }
    }
  }

  // --- LOGIKA DATABASE & SENSOR ---
  void _initListeners() {
    // SUHU
    _dbRef.child('Dapur/Suhu').onValue.listen((e) {
      if (e.snapshot.value != null && mounted) {
        setState(() {
          suhu = e.snapshot.value.toString();
          isConnected = true;
          _updateChart(double.tryParse(suhu) ?? 0, null);
        });
      }
    });

    // KELEMBAPAN
    _dbRef.child('Dapur/Kelembapan').onValue.listen((e) {
      if (mounted) setState(() => hum = e.snapshot.value.toString());
    });

    // GAS & BAHAYA
    _dbRef.child('Dapur/Gas').onValue.listen((e) {
      if (e.snapshot.value != null && mounted) {
        setState(() {
          gas = e.snapshot.value.toString();
          double gasVal = double.tryParse(gas) ?? 0;

          _updateChart(null, gasVal);
          _checkDanger(gasVal); // Cek bahaya setiap data masuk
        });
      }
    });
  }

  // --- LOGIKA CHART (Updated) ---
  void _updateChart(double? t, double? g) {
    if (suhuPoints.length > 20) {
      suhuPoints.removeAt(0);
      gasPoints.removeAt(0);
    }

    // Logic agar grafik selalu sinkron X-nya
    if (t != null) {
      suhuPoints.add(FlSpot(xValue, t));
      // Jika data gas belum masuk, pakai data terakhir
      if (gasPoints.length < suhuPoints.length) {
        gasPoints.add(
          FlSpot(xValue, gasPoints.isNotEmpty ? gasPoints.last.y : 0),
        );
      }
      xValue++;
    } else if (g != null) {
      // Jika update gas, update titik terakhir (karena biasanya suhu yg trigger xValue++)
      if (gasPoints.isNotEmpty) {
        final lastX = gasPoints.last.x;
        gasPoints.removeLast();
        gasPoints.add(FlSpot(lastX, g / 10)); // Bagi 10 agar skala masuk akal
      } else {
        gasPoints.add(FlSpot(xValue, g / 10));
      }
    }
  }

  // --- LOGIKA BAHAYA (FIXED) ---
  void _checkDanger(double gasVal) {
    if (gasVal > batasBahayaGas) {
      if (!isDangerMode) {
        isDangerMode = true; // Masuk mode bahaya
        _triggerDangerProtocol();
      }
    } else {
      if (isDangerMode) {
        isDangerMode = false; // Kembali aman
        audioPlayer.stop();
      }
    }
  }

  void _triggerDangerProtocol() async {
    // 1. Notifikasi
    if (fiturNotifikasi) {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'danger_channel',
            'Bahaya Gas',
            importance: Importance.max,
            priority: Priority.high,
            color: Colors.red,
          );
      await flutterLocalNotificationsPlugin.show(
        0,
        "BAHAYA TERDETEKSI!",
        "Kadar gas tinggi: $gas PPM",
        const NotificationDetails(android: androidDetails),
      );
    }

    // 2. TTS Robot (Debounced 5 detik agar tidak cerewet)
    if (fiturSuaraRobot && (_ttsTimer == null || !_ttsTimer!.isActive)) {
      await flutterTts.speak("Peringatan! Bahaya gas terdeteksi.");
      _ttsTimer = Timer(const Duration(seconds: 5), () {});
    }

    // 3. Audio Sirine
    if (fiturAlarmSuara) {
      // Menggunakan beep online
      await audioPlayer.play(
        UrlSource('https://www.soundjay.com/buttons/beep-07.mp3'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double gasVal = double.tryParse(gas) ?? 0;
    final bool isBahaya = gasVal > batasBahayaGas;

    // Warna background berubah soft red jika bahaya
    Color safeBg = Theme.of(context).scaffoldBackgroundColor;
    Color dangerBg = isDark
        ? Colors.red.shade900.withValues(alpha: 0.3)
        : Colors.red.shade50;

    return Container(
      color: isBahaya ? dangerBg : safeBg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Dapur Pintar AI",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      isConnected ? "● Terhubung" : "○ Menunggu...",
                      style: TextStyle(
                        color: isConnected ? Colors.green : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                  onPressed: () {
                    _themeNotifier.value = isDark
                        ? ThemeMode.light
                        : ThemeMode.dark;
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // KARTU AI GEMINI (GRADIENT)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF4A148C), const Color(0xFF1A237E)]
                      : [const Color(0xFFE1BEE7), const Color(0xFFBBDEFB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.purple.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome, color: Colors.amber),
                          const SizedBox(width: 8),
                          Text(
                            "Analisis AI Gemini",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      if (isAiLoading)
                        const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    aiResponse,
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isAiLoading ? null : _askGemini,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.white,
                        foregroundColor: isDark ? Colors.white : Colors.purple,
                        elevation: 0,
                      ),
                      child: const Text("Minta Pendapat AI"),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // SENSOR GRID
            Row(
              children: [
                Expanded(
                  child: _buildInfoCard(
                    "Suhu",
                    "$suhu°C",
                    Icons.thermostat,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _buildInfoCard(
                    "Lembap",
                    "$hum%",
                    Icons.water_drop,
                    Colors.cyan,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            _buildInfoCard(
              "Kualitas Udara (Gas)",
              "$gas PPM",
              Icons.cloud,
              isBahaya ? Colors.red : Colors.green,
            ),

            const SizedBox(height: 20),

            // CHART CONTAINER
            Container(
              height: 300,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Grafik Realtime",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    "Biru: Suhu | Merah: Gas (skala/10)",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: suhuPoints.isEmpty
                        ? const Center(child: Text("Menunggu Data..."))
                        : LineChart(
                            LineChartData(
                              gridData: const FlGridData(show: false),
                              titlesData: const FlTitlesData(show: false),
                              borderData: FlBorderData(
                                show: true,
                                border: Border.all(
                                  color: Colors.grey.withValues(alpha: 0.2),
                                ),
                              ),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: suhuPoints,
                                  isCurved: true,
                                  color: Colors.blue,
                                  barWidth: 3,
                                  dotData: const FlDotData(show: false),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: Colors.blue.withValues(alpha: 0.1),
                                  ),
                                ),
                                LineChartBarData(
                                  spots: gasPoints, // Sudah dibagi 10 di logic
                                  isCurved: true,
                                  color: Colors.red,
                                  barWidth: 3,
                                  dotData: const FlDotData(show: false),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 15),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }
}

// --- LOGS TAB (Placeholder Sederhana) ---
class LogsTab extends StatelessWidget {
  const LogsTab({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_edu, size: 60, color: Colors.grey[400]),
          const SizedBox(height: 20),
          const Text("Riwayat & Pengaturan"),
          const Text("(Fitur ini bisa ditambahkan di update berikutnya)"),
        ],
      ),
    );
  }
}
