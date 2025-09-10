import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'database_helper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late DateTime _fromDate;
  late DateTime _toDate;
  bool _isLoading = false;
  List<Map<String, dynamic>> _records = [];
  final DateFormat _displayFormat = DateFormat('dd-MM-yyyy');
  final Color customBlue = const Color(0xFF002DB2);

  @override
  void initState() {
    super.initState();
    _fromDate = DateTime.now().subtract(const Duration(days: 7));
    _toDate = DateTime.now();
  }

  Future<void> _searchRecords() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final records = await DatabaseHelper.instance.getDataBetweenDates(
        _fromDate.toIso8601String(),
        _toDate.toIso8601String(),
      );

      if (!mounted) return;
      setState(() => _records = records);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _shareViaWhatsApp() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      if (_records.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No records available to share')),
          );
        }
        return;
      }

      final pdfBytes = await _generatePdfReport(_records);
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(pdfBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Monitoring Report',
        subject: 'Monitoring Report',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<Uint8List> _generatePdfReport(
    List<Map<String, dynamic>> records,
  ) async {
    final pdf = pw.Document();
    final dateFormat = DateFormat('dd-MM-yyyy');

    PdfColor getStatusColor(int groundValue) {

    if (groundValue >= 0 && groundValue <= 18) {
        return PdfColors.red;
    } else if (groundValue >= 19 && groundValue <= 72) {
        return PdfColors.yellow;
    } else if (groundValue >= 73 && groundValue <= 216) {
        return PdfColors.green;
    } else if (groundValue >= 217 && groundValue <= 306) {
        return PdfColors.yellow;
    } else if (groundValue >= 307 && groundValue <= 360) {
        return PdfColors.red;
    }
     /*  if (groundValue == 0) {
        return PdfColors.red;
      } else if (groundValue > 0 && groundValue < 10) {
        return PdfColors.orange;
      } else if (groundValue >= 10 && groundValue < 40) {
        return PdfColors.blue;
      } else if (groundValue >= 40 && groundValue < 50) {
        return PdfColors.purple;
      } else if (groundValue >= 50) {
        return PdfColors.red;
      } */
      return PdfColors.black;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'Monitoring Report',
              style: pw.TextStyle(fontSize: 24),
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Date Range: ${dateFormat.format(_fromDate)} - ${dateFormat.format(_toDate)}',
          ),
          pw.SizedBox(height: 20),
          pw.Table(
            border: pw.TableBorder.all(),
            children: [
              pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(
                      'Date',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(
                      'Estimated Hits Sensing',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(
                      'Status',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ],
              ),
              for (var record in records)
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(
                        dateFormat.format(DateTime.parse(record['datetime'])),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(record['estimated_volml'].toString()),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(
                        record['status'] ?? 'N/A',
                        style: pw.TextStyle(
                          color: getStatusColor(
                            (record['estimated_volml'] is num)
                                ? record['estimated_volml'].toInt()
                                : int.tryParse(
                                        record['estimated_volml'].toString(),
                                      ) ??
                                      0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  Future<void> _selectDateTime(bool isFromDate) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isFromDate ? _fromDate : _toDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (date == null || !mounted) return;

    if (mounted) {
      setState(() {
        if (isFromDate) {
          _fromDate = DateTime(date.year, date.month, date.day);
        } else {
          _toDate = DateTime(date.year, date.month, date.day, 23, 59, 59);
        }
      });
    }
  }

  // 2. Then in your _HistoryPageState class, include this method:
  Widget _buildHistogram() {
    final categories = [
      HistogramCategory(
        'A: Total Catheter Blockage',
        Colors.red,
        (volml) => volml == 0,
      ),
      HistogramCategory(
        'B: Partially Closed',
        Colors.orange,
        (volml) => volml > 0 && volml < 10,
      ),
      HistogramCategory(
        'C: Normal Flow',
        Colors.green,
        (volml) => volml >= 10 && volml < 40,
      ),
      HistogramCategory(
        'D: Overflow',
        Colors.blue,
        (volml) => volml >= 40 && volml < 50,
      ),
      HistogramCategory(
        'E: Draining output full / air lock',
        Colors.purple,
        (volml) => volml >= 50,
      ),
    ];

    final totalRecords = _records.length;
    final histogramData = categories.map((category) {
      final count = _records.where((r) {
        final value = r['estimated_volml'];
        final volml = value == null
            ? 0.0
            : value is num
            ? value.toDouble()
            : double.tryParse(value.toString()) ?? 0.0;
        return category.condition(volml);
      }).length;

      final percentage = totalRecords > 0
          ? ((count / totalRecords) * 100).round()
          : 0;
      return HistogramData(category.label, percentage, category.color);
    }).toList();

    final maxValue = histogramData.isNotEmpty
        ? histogramData.map((e) => e.value).reduce((a, b) => a > b ? a : b)
        : 1;
    final scaleMax = maxValue > 0 ? maxValue : 1;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 8), // Reduced from 20
      child: Padding(
        padding: const EdgeInsets.all(12), // Reduced from 16
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Estimated Status (%)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ), // Smaller font
            ),
            const SizedBox(height: 8), // Reduced from 20

            SizedBox(
              height: 180, // Reduced from 250
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: histogramData.map((item) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (item.value == 0)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 2), // Reduced from 4
                          child: Text(
                            '0%',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 12, // Smaller font
                            ),
                          ),
                        ),
                      Container(
                        width: 24, // Narrower from 30
                        height: item.value == 0
                            ? 2
                            : 140 * (item.value / scaleMax), // Shorter bars
                        decoration: BoxDecoration(
                          color: item.color,
                          borderRadius: BorderRadius.circular(
                            3,
                          ), // Smaller radius
                        ),
                        child: item.value > 0
                            ? Center(
                                child: Text(
                                  '${item.value}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 9, // Smaller font
                                  ),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 4), // Reduced from 8
                      SizedBox(
                        width: 24, // Narrower from 30
                        child: Text(
                          item.label.substring(0, 1),
                          style: const TextStyle(fontSize: 14), // Smaller font
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8), // Reduced from 20

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: categories.map((category) {
                    return Padding(
                      padding: const EdgeInsets.only(
                        bottom: 4,
                      ), // Reduced from 8
                      child: Row(
                        children: [
                          Container(
                            width: 14, // Smaller from 14
                            height: 14, // Smaller from 14
                            color: category.color,
                            margin: const EdgeInsets.only(
                              right: 6,
                            ), // Reduced from 8
                          ),
                          Text(
                            category.label,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ), // Smaller from 12
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Total:',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                      ), // Smaller
                    ),
                    Text(
                      '$totalRecords',
                      style: const TextStyle(
                        fontSize: 14, // Smaller from 16
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History Records')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildDateSelectionCard(),
            const SizedBox(height: 10),
            _buildSearchButton(),
            const SizedBox(height: 10),
            _buildWhatsAppButton(),
            const SizedBox(height: 5),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildHistogram(),
                    _buildResultsHeader(),
                    _buildRecordsList(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelectionCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Select Date Range',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('From Date'),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _selectDateTime(true),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: customBlue),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: customBlue),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: customBlue, width: 2.0),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _displayFormat.format(_fromDate),
                          style: TextStyle(color: customBlue),
                        ),
                        Icon(Icons.calendar_today, color: customBlue),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('To Date'),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _selectDateTime(false),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: customBlue),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: customBlue),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: customBlue, width: 2.0),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _displayFormat.format(_toDate),
                          style: TextStyle(color: customBlue),
                        ),
                        Icon(Icons.calendar_today, color: customBlue),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _searchRecords,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: customBlue,
          foregroundColor: Colors.white,
        ),
        child: _isLoading
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      //color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text('Wait...', style: TextStyle(fontSize: 16)),
                ],
              )
            : const Text('Search Records', style: TextStyle(fontSize: 16)),
      ),
    );
  }

  Widget _buildWhatsAppButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _shareViaWhatsApp,
        icon: const Icon(Icons.send),
        label: const Text('Share Report'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildResultsHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Results (${_records.length})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (_records.isNotEmpty)
            TextButton(
              onPressed: () async {
                try {
                  if (!mounted) return;
                  setState(() => _isLoading = true);

                  final pdfBytes = await _generatePdfReport(_records);

                  if (!mounted) return;
                  await Printing.layoutPdf(onLayout: (_) => pdfBytes);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Print Error: ${e.toString()}')),
                    );
                  }
                } finally {
                  if (mounted) {
                    setState(() => _isLoading = false);
                  }
                }
              },
              child: Row(
                children: [
                  Icon(Icons.print, color: customBlue),
                  const SizedBox(width: 4),
                  Text('Print', style: TextStyle(color: customBlue)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecordsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_records.isEmpty) {
      return const Center(
        child: Text('No records found', style: TextStyle(fontSize: 16)),
      );
    }

    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: _records.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final record = _records[index];
        final int groundValue = (record['estimated_volml'] is num)
            ? record['estimated_volml'].toInt()
            : int.tryParse(record['estimated_volml'].toString()) ?? 0;

        Color statusColor = Colors.black;
        if (groundValue >= 0 && groundValue <= 18) {
              statusColor = Colors.red;
        } else if (groundValue >= 19 && groundValue <= 72) {
              statusColor = Colors.yellow;
        } else if (groundValue >= 73 && groundValue <= 216) {
              statusColor = Colors.green;
        } else if (groundValue >= 217 && groundValue <= 306) {
              statusColor = Colors.yellow;
        } else if (groundValue >= 307 && groundValue <= 360) {
              statusColor = Colors.red;
        }
       /*  if (groundValue == 0) {
          statusColor = Colors.red;
        } else if (groundValue < 10) {
          statusColor = Colors.orange;
        } else if (groundValue >= 10 && groundValue < 40) {
          statusColor = Colors.blue;
        } else if (groundValue >= 40 && groundValue < 50) {
          statusColor = Colors.deepPurpleAccent;
        } else if (groundValue >= 60) {
          statusColor = Colors.red;
        } */

        return ListTile(
          title: Text(
            _displayFormat.format(DateTime.parse(record['datetime'])),
          ),
          subtitle: Text(
            'Battery: ${record['battery']}V | Estimated Hits Sensing: ${record['estimated_volml']}',
          ),
          trailing: Text(
            record['status'] ?? 'N/A',
            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
          ),
        );
      },
    );
  }
}

// 1. First, define these classes at the TOP LEVEL of your file (outside any other class)
class HistogramCategory {
  final String label;
  final Color color;
  final bool Function(double) condition;

  const HistogramCategory(this.label, this.color, this.condition);
}

class HistogramData {
  final String label;
  final int value;
  final Color color;

  const HistogramData(this.label, this.value, this.color);
}
