// histo_page.dart
import 'package:flutter/material.dart';

class HistogramPage extends StatelessWidget {
  const HistogramPage({super.key});

  final List<HistogramData> data = const [
    HistogramData('Jan', 15),
    HistogramData('Feb', 28),
    HistogramData('Mar', 22),
    HistogramData('Apr', 34),
    HistogramData('May', 40),
    HistogramData('Jun', 30),
  ];

  @override
  Widget build(BuildContext context) {
    double maxValue = data.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble();

    return Scaffold(
      appBar: AppBar(title: const Text('Histogram Example')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Monthly Sales Data',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: data.map((item) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 40,
                        height: 200 * (item.value / maxValue),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: Text(
                            item.value.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(item.label),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Months',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class HistogramData {
  final String label;
  final int value;

  const HistogramData(this.label, this.value);
}
