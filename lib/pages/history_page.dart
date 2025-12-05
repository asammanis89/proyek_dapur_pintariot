import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'dart:typed_data';

// --- LOGS TAB ---
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final DatabaseReference _logsRef = FirebaseDatabase.instance.ref('logs');
  String _filter = 'all'; // 'all' | 'gas' | 'temperature'

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
          child: Row(
            children: [
              const Text('Filter:'),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('All'),
                selected: _filter == 'all',
                onSelected: (_) => setState(() => _filter = 'all'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Gas'),
                selected: _filter == 'gas',
                onSelected: (_) => setState(() => _filter = 'gas'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Temperature'),
                selected: _filter == 'temperature',
                onSelected: (_) => setState(() => _filter = 'temperature'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Export to PDF',
                icon: const Icon(Icons.picture_as_pdf),
                onPressed: _exportLogsToPdf,
              ),
              const Spacer(),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<DatabaseEvent>(
            stream: _logsRef.orderByChild('datetime').onValue,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_edu, size: 60, color: Colors.grey[400]),
                      const SizedBox(height: 20),
                      const Text('Riwayat Peringatan'),
                      const SizedBox(height: 6),
                      const Text('Belum ada catatan peringatan.'),
                    ],
                  ),
                );
              }

              final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;

              // Convert map to list and sort by datetime desc (newest first)
              final List<MapEntry<dynamic, dynamic>> entries = data.entries.toList();
              entries.sort((a, b) {
                final da = a.value['datetime']?.toString() ?? '';
                final db = b.value['datetime']?.toString() ?? '';
                return db.compareTo(da);
              });

              // Apply filter
              final filtered = entries.where((e) {
                if (_filter == 'all') return true;
                final reason = e.value['reason']?.toString() ?? '';
                return reason == _filter;
              }).toList();

              if (filtered.isEmpty) {
                return Center(child: Text('No logs for selected filter.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final item = filtered[index].value as Map<dynamic, dynamic>;
                  return _buildLogCard(context, item);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _exportLogsToPdf() async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      // show temporary progress
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final dbSnap = await _logsRef.get();
      if (!dbSnap.exists || dbSnap.value == null) {
        Navigator.of(context).pop();
        scaffold.showSnackBar(const SnackBar(content: Text('No logs to export')));
        return;
      }

      final data = dbSnap.value as Map<dynamic, dynamic>;
      final entries = data.entries.toList();
      // sort newest first by datetime
      entries.sort((a, b) {
        final da = a.value['datetime']?.toString() ?? '';
        final db = b.value['datetime']?.toString() ?? '';
        return db.compareTo(da);
      });

      final pdf = pw.Document();

      // Prepare table data
      final headers = ['Tanggal', 'Jam', 'Peringatan', 'Suhu', 'Gas'];
      final List<List<String>> dataRows = entries.map((e) {
        final item = e.value as Map<dynamic, dynamic>;
        final date = item['date']?.toString() ?? '';
        final time = item['time']?.toString() ?? '';
        final desc = item['description']?.toString() ?? item['reason']?.toString() ?? '';
        final suhu = item['suhu'] != null && item['suhu'].toString().isNotEmpty ? '${item['suhu'].toString()} C' : '';
        final gas = item['gas'] != null && item['gas'].toString().isNotEmpty ? '${item['gas'].toString()} PPM' : '';
        return [date, time, desc, suhu, gas];
      }).toList();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context ctx) {
            return [
              pw.Header(level: 0, child: pw.Text('Dapur Pintar - Logs', style: pw.TextStyle(fontSize: 18))),
              pw.SizedBox(height: 8),
              pw.Table.fromTextArray(
                headers: headers,
                data: dataRows,
                headerStyle: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                cellAlignment: pw.Alignment.centerLeft,
                cellStyle: pw.TextStyle(fontSize: 11),
                columnWidths: {
                  0: const pw.FixedColumnWidth(70), // date
                  1: const pw.FixedColumnWidth(60), // time
                  2: const pw.FlexColumnWidth(), // description
                  3: const pw.FixedColumnWidth(60), // suhu
                  4: const pw.FixedColumnWidth(70), // gas
                },
              ),
            ];
          },
        ),
      );

      final Uint8List bytes = await pdf.save();
      Navigator.of(context).pop(); // close progress

      final now = DateTime.now();
      final filename = 'dapur_logs_${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}.pdf';

      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (e) {
      Navigator.of(context).pop();
      final scaffold = ScaffoldMessenger.of(context);
      scaffold.showSnackBar(SnackBar(content: Text('Failed to export PDF: $e')));
    }
  }

  // Removed _buildPdfLogItem: using table layout instead.

  Widget _buildLogCard(BuildContext context, Map<dynamic, dynamic> item) {
    final reason = item['reason']?.toString() ?? 'unknown';
    final description = item['description']?.toString() ?? '';
    final date = item['date']?.toString() ?? '';
    final time = item['time']?.toString() ?? '';
    final detected = item['detected_value']?.toString() ?? '';
    final suhu = item['suhu']?.toString() ?? '';
    final gas = item['gas']?.toString() ?? '';

    Color badgeColor;
    IconData badgeIcon;
    String badgeText;
    if (reason == 'temperature') {
      badgeColor = Colors.orange;
      badgeIcon = Icons.thermostat;
      badgeText = 'Suhu';
    } else if (reason == 'gas') {
      badgeColor = Colors.red;
      badgeIcon = Icons.cloud;
      badgeText = 'Gas';
    } else {
      badgeColor = Colors.grey;
      badgeIcon = Icons.warning;
      badgeText = 'Lainnya';
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: badgeColor.withOpacity(0.12),
          child: Icon(badgeIcon, color: badgeColor),
        ),
        title: Text(description, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Text('$date • $time'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(badgeText, style: TextStyle(color: badgeColor, fontSize: 12)),
                ),
                Text('Value: $detected', style: const TextStyle(fontSize: 12)),
                Text('S: $suhu', style: const TextStyle(fontSize: 12)),
                Text('G: $gas', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        onTap: () => _openDetails(context, item),
      ),
    );
  }

  void _openDetails(BuildContext context, Map<dynamic, dynamic> item) {
    // final datetime = item['datetime']?.toString() ?? '';
    final date = item['date']?.toString() ?? '';
    final time = item['time']?.toString() ?? '';
    final reason = item['reason']?.toString() ?? '';
    final description = item['description']?.toString() ?? '';
    // final detected = item['detected_value']?.toString() ?? '';
    final suhu = item['suhu']?.toString() ?? '';
    final gas = item['gas']?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(description, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Tanggal: $date'),
              Text('Waktu: $time'),
              const SizedBox(height: 8),
              Text('Peringatan: $reason'),
              Text('Suhu: $suhu'),
              Text('Gas: $gas'),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
