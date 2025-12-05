import 'package:flutter/material.dart';

// --- LOGS TAB ---
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

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
