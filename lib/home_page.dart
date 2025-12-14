import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'database_helper.dart';
import 'history_page.dart';
import 'package:intl/intl.dart';
//import 'multiplied_page.dart';
import 'dart:math';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // BLE Service and Characteristics UUIDs
  static const String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String logCharUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  static const String cmdCharUuid = "1c95d5e3-d8f7-413a-bf3d-7a2e5d7b5e1a";
  static const String statusCharUuid = "3c59e153-6d8a-4e36-9a7f-9b9a1d3b5c7d";

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _logCharacteristic;
  BluetoothCharacteristic? _cmdCharacteristic;
  BluetoothCharacteristic? _statusCharacteristic;

  String _status = "Disconnected";
  bool _isConnecting = false;
  bool _isScanning = false;

  // Add this variable
  int _volumeMultiplier = 1;

  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _deviceStateSubscription;
  StreamSubscription<List<int>>? _notificationSubscription;

  final List<ScanResult> _foundDevices = [];
  final List<Map<String, dynamic>> _parsedLogs = [];

  Map<String, dynamic>? _latestUpdate;

  // Database helper instance
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // Add these instance variables for delayed processing
  Timer? _processTimer;
  final Duration _processingDelay = const Duration(seconds: 5);
  String _logBuffer = '';
  DateTime _lastProcessedTime = DateTime.now();
  bool _isFirstDataChunk = true;
  int _totalRecordsProcessed = 0;

  // Add these for tracking consecutive calls
  int _lastCondition = -1;
  int _consecutiveCount = 0;

  List<String> logMessages = [];

  void addToLog(String message) {
    if (mounted) {
      setState(() {
        logMessages.insert(0, message);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMultiplier();
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        setState(() => _status = "Ready to scan");
      } else {
        setState(
          () => _status = "Bluetooth is ${state.toString().split('.').last}",
        );
      }
    });
  }

  // Add this method to load the multiplier
  Future<void> _loadMultiplier() async {
    try {
      final multiplier = 1; //await _dbHelper.getVolumeValue();
      setState(() => _volumeMultiplier = multiplier);
    } catch (e) {
      debugPrint('Error loading multiplier: $e');
    }
  }

  Future<void> _scanForDevices() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _isConnecting = false;
      _status = "Scanning for Retinco devices...";
      _foundDevices.clear();
      _parsedLogs.clear();
      _latestUpdate = null;
      // Reset processing variables
      _logBuffer = '';
      _processTimer?.cancel();
      _isFirstDataChunk = true;
      _totalRecordsProcessed = 0;
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: false,
      );

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        for (final result in results) {
          // Only consider devices with the expected Retinco name
          if (result.device.platformName == 'RETINCO_DEVICE') {
            if (!_foundDevices.any(
              (r) => r.device.remoteId == result.device.remoteId,
            )) {
              setState(() => _foundDevices.add(result));
            }

            // Auto-connect to the first matching device
            if (_connectedDevice == null && !_isConnecting) {
              await FlutterBluePlus.stopScan();
              _connectToDevice(result.device);
              break;
            }
          }
        }
      });

      await Future.delayed(const Duration(seconds: 15));
      await FlutterBluePlus.stopScan();

      setState(() {
        _isScanning = false;
        if (_foundDevices.isEmpty) {
          _status = "No Retinco devices found";
        } else {
          _status = "Found ${_foundDevices.length} Retinco device(s)";
        }
      });
    } catch (e) {
      setState(() {
        _isScanning = false;
        _status = "Scan error: Please turn your Bluetooth ON.";
      });
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _status = "Connecting to ${device.platformName}...";
      _parsedLogs.clear();
      _latestUpdate = null;
      // Reset processing variables
      _logBuffer = '';
      _processTimer?.cancel();
      _isFirstDataChunk = true;
      _totalRecordsProcessed = 0;
    });

    try {
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );

      setState(() {
        _connectedDevice = device;
        _status = "Connected to ${device.platformName}";
      });

      _deviceStateSubscription = device.connectionState.listen((state) async {
        if (state == BluetoothConnectionState.disconnected) {
          setState(() {
            _status = "Disconnected";
            _logCharacteristic = null;
            _cmdCharacteristic = null;
            _statusCharacteristic = null;
            _foundDevices.clear();
            // Cancel any pending processing
            _processTimer?.cancel();
          });
        }
      });

      await _discoverServices(device);

      // Automatically send READ_LOG command after connection
      if (_cmdCharacteristic != null) {
        await _sendCommand('READ_LOG');
      }
    } catch (e) {
      setState(
        () => _status =
            "Connection failed: Please check if your device bluetooth is ON",
      );
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  Future<void> _discoverServices(BluetoothDevice device) async {
    try {
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid == Guid(serviceUuid)) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid == Guid(logCharUuid)) {
              _logCharacteristic = characteristic;

              await characteristic.setNotifyValue(true);
              _notificationSubscription = characteristic.lastValueStream.listen(
                _onDataReceived,
              );
            } else if (characteristic.uuid == Guid(cmdCharUuid)) {
              _cmdCharacteristic = characteristic;
            } else if (characteristic.uuid == Guid(statusCharUuid)) {
              _statusCharacteristic = characteristic;
            }
          }
        }
      }

      if (_logCharacteristic == null ||
          _cmdCharacteristic == null ||
          _statusCharacteristic == null) {
        setState(() => _status = "Missing some characteristics");
      } else {
        setState(() => _status = "Ready to Retrieve Data");
      }
    } catch (e) {
      setState(() => _status = "Service discovery failed: ${e.toString()}");
    }
  }

  // Add this helper function to generate random numbers with two decimals
  double _generateRandomNumber(double min, double max) {
    final random = Random();
    double value = min + random.nextDouble() * (max - min);
    return double.parse(value.toStringAsFixed(2));
  }

  // Add this helper method to get status and color
  (String, Color) _getStatusForGround(double ground) {
    if (ground >= 3 && ground < 10) {
      return ("Total Blockage", Colors.red);
    } else {
      return ("", Colors.transparent);
    }
  }

  // Modified _onDataReceived with 8-second delay
  void _onDataReceived(List<int> data) {
    try {
      String chunk = utf8.decode(data, allowMalformed: true);
      _logBuffer += chunk;

      // Cancel previous timer and start a new one
      _processTimer?.cancel();
      _processTimer = Timer(_processingDelay, _processBufferedData);

      // Update status to show data is being received
      if (mounted) {
        setState(() {
          _status = "Receiving data... (${_logBuffer.length} bytes buffered)";
        });
      }
    } catch (e) {
      addToLog("Data processing error: ${e.toString()}");
      _logBuffer = '';
    }
  }

  void _processBufferedData() {
    try {
      if (_logBuffer.isEmpty) return;

      // Find the last newline to separate complete vs incomplete data
      int lastNewlineIndex = _logBuffer.lastIndexOf('\n');

      String completeData;
      if (lastNewlineIndex != -1) {
        // Extract complete lines (everything up to last newline)
        completeData = _logBuffer.substring(0, lastNewlineIndex);

        // Keep incomplete line (everything after last newline) in buffer
        _logBuffer = _logBuffer.substring(lastNewlineIndex + 1);
      } else {
        // No newline found - process everything and clear buffer
        completeData = _logBuffer;
        _logBuffer = '';
      }

      // Process complete lines
      if (completeData.isNotEmpty) {
        //completeData ='[2]300,1\n[2]300,2\n[2]75,3\n[2]309,4\n[2]18,5\n[2]300,6\n[2]300,7\n[2]75,8\n[2]309,9\n';
        List<String> lines = completeData.split('\n');
        List<String> nonEmptyLines = lines
            .where((line) => line.isNotEmpty)
            .toList();

        if (nonEmptyLines.isNotEmpty) {
          _processLogLines(nonEmptyLines);
        }
      }

      // Update status
      if (mounted) {
        setState(() {
          _status =
              "Data processing Complete. ${_parsedLogs.length} records received.";
        });
      }
    } catch (e) {
      addToLog("Buffered data processing error: ${e.toString()}");
      _logBuffer = '';
    } finally {
      _processTimer = null;
    }
  }

  void _processLogLines(List<String> lines) {
    List<Map<String, dynamic>> validLogs = [];

    // Use instance variable for consistent time tracking
    DateTime processingTime = _lastProcessedTime;
    int processedCount = 0;

    // Process in chronological order (newest first)
    for (int i = lines.length - 1; i >= 0; i--) {
      String line = lines[i].trim();
      if (line.isEmpty) continue;

      // Remove [2] prefix if present
      if (line.startsWith('[2]')) {
        line = line.substring(3);
      }

      List<String> parts = line.split(',');
      if (parts.length != 2) continue;

      try {
        int ground = int.parse(parts[0].trim());
        double bat = double.parse(parts[1].trim());
        if (bat == 0.0) continue;

        int multipliedGround = ground * _volumeMultiplier;
        double randomValue = _calculateRandomValue(multipliedGround);
        var (statusText, _) = _getStatusForGround(randomValue);

        // Calculate time - subtract 30 minutes for each record
        DateTime recordTime;
        if (_isFirstDataChunk && processedCount == 0) {
          // First record of first chunk uses current time
          recordTime = DateTime.now();
        } else {
          // Subsequent records go backwards in time
          recordTime = processingTime.subtract(const Duration(minutes: 30));
        }

        String formattedTime = DateFormat(
          'dd-MM-yyyy HH:mm:ss',
        ).format(recordTime);

        Map<String, dynamic> parsed = {
          'ground': randomValue,
          'bat': bat,
          'timestamp': recordTime.toIso8601String(),
          'logTime': formattedTime,
          'formattedTime': formattedTime,
          'status': statusText,
        };

        validLogs.add(parsed);
        processedCount++;

        // Update the processing time for next record
        processingTime = recordTime;
      } catch (e) {
        debugPrint('Error parsing line: $line, error: $e');
        continue;
      }
    }

    if (validLogs.isNotEmpty) {
      setState(() {
        _parsedLogs.insertAll(0, validLogs);
        _latestUpdate = {
          'ground': validLogs.first['ground'] ?? 0,
          'bat': validLogs.first['bat'],
          'formattedTime': validLogs.first['formattedTime'],
          'status': validLogs.first['status'],
        };
      });

      // Update last processed time for next chunk
      _lastProcessedTime = processingTime;
      _isFirstDataChunk = false;
      _totalRecordsProcessed += processedCount;

      // Save to database
      for (var log in validLogs.reversed) {
        _insertDataIntoDatabase(log);
      }

      addToLog(
        "Processed $processedCount records. Total: $_totalRecordsProcessed",
      );
      _sendCommand('CLEAR_LOG');
    }
  }

  /*  double _calculateRandomValue(int ground) {
    if (ground >= 0 && ground <= 18) return _generateRandomNumber(3.0, 9.0);
    if (ground >= 19 && ground <= 72) return _generateRandomNumber(10.0, 20.0);
    if (ground >= 73 && ground <= 306) return _generateRandomNumber(21.0, 33.0);
    if (ground > 306) return _generateRandomNumber(34.0, 40.0);
    return ground.toDouble();
  } */

  double _calculateRandomValue(int ground) {
    // Determine current condition
    int currentCondition;
    if (ground >= 0 && ground <= 18) {
      currentCondition = 1;
    } else if (ground >= 19 && ground <= 72) {
      currentCondition = 2;
    } else if (ground >= 73 && ground <= 306) {
      currentCondition = 3;
    } else if (ground > 306) {
      currentCondition = 4;
    } else {
      currentCondition = 0;
    }

    // Check if same condition is called consecutively
    if (currentCondition == _lastCondition) {
      _consecutiveCount++;
    } else {
      _consecutiveCount = 1;
      _lastCondition = currentCondition;
    }

    double result;

    // Apply special rules for the THIRD consecutive call
    if (_consecutiveCount >= 3) {
      if (currentCondition == 4) {
        // ground > 306
        result = _generateRandomNumber(27.0, 29.0);
      } else if (currentCondition == 3) {
        // ground >= 73 && ground <= 306
        result = _generateRandomNumber(19.0, 20.0);
      } else {
        // Fall back to default ranges for other conditions
        result = _getDefaultRange(ground);
      }

      // RESET the counter after applying the special logic
      _consecutiveCount = 0;
      _lastCondition = -1; // Also reset last condition to ensure fresh start
    } else {
      // Use default ranges for first and second calls
      result = _getDefaultRange(ground);
    }

    return result;
  }

  double _getDefaultRange(int ground) {
    if (ground >= 0 && ground <= 18) return _generateRandomNumber(3.0, 9.0);
    if (ground >= 19 && ground <= 72) return _generateRandomNumber(10.0, 20.0);
    if (ground >= 73 && ground <= 306) return _generateRandomNumber(21.0, 33.0);
    if (ground > 306) return _generateRandomNumber(34.0, 40.0);
    return ground.toDouble();
  }

  Future<void> _insertDataIntoDatabase(Map<String, dynamic> parsedData) async {
    try {
      final Map<String, dynamic> row = {
        'battery': parsedData['bat'],
        'estimated_volml': parsedData['ground'],
        'status': parsedData['status'],
        'datetime': parsedData['formattedTime'],
      };

      await _dbHelper.insertData(row);
    } catch (e) {
      debugPrint('Error inserting data: $e');
      if (mounted) {
        setState(() => _status = "DB Error: ${e.toString()}");
      }
    }
  }

  Future<void> _sendCommand(String command) async {
    if (_cmdCharacteristic == null) return;

    try {
      await _cmdCharacteristic!.write(utf8.encode(command));
    } catch (e) {
      if (mounted) {
        setState(() => _status = "Command failed: ${e.toString()}");
      }
    }
  }

  Future<void> _disconnectDevice() async {
    // Cancel any pending processing
    _processTimer?.cancel();

    if (_connectedDevice != null) {
      setState(() => _status = "Disconnecting...");
      await _connectedDevice!.disconnect();
      _deviceStateSubscription?.cancel();
      _notificationSubscription?.cancel();
      setState(() {
        _logCharacteristic = null;
        _cmdCharacteristic = null;
        _statusCharacteristic = null;
        _foundDevices.clear();
        _status = "Disconnected";
      });
    }
  }

  Future<void> _reloadApp() async {
    // Cancel any pending processing
    _processTimer?.cancel();

    if (_connectedDevice != null) {
      setState(() => _status = "Disconnecting...");
      await _connectedDevice!.disconnect();
      _deviceStateSubscription?.cancel();
      _notificationSubscription?.cancel();
      setState(() {
        _connectedDevice = null;
        _logCharacteristic = null;
        _cmdCharacteristic = null;
        _statusCharacteristic = null;
        _parsedLogs.clear();
        _latestUpdate = null;
        _status = "Disconnected";
        _foundDevices.clear();
        // Reset processing variables
        _logBuffer = '';
        _isFirstDataChunk = true;
        _totalRecordsProcessed = 0;
        // Reset consecutive counters
        _lastCondition = -1;
        _consecutiveCount = 0;
      });
    }
  }

  // Update UI to show status in log list
  Widget _buildLogListView() {
    // Filter out logs with null or zero battery values
    final validLogs = _parsedLogs.where((log) {
      final battery = log['bat'];
      return battery != null && battery != 0.0;
    }).toList();

    if (validLogs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No valid data received yet.\nEnsure battery values are present and non-zero.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: validLogs.length,
      itemBuilder: (context, index) {
        final entry = validLogs[index];
        final (statusText, statusColor) = _getStatusForGround(entry['ground']);

        return Card(
          margin: const EdgeInsets.all(4.0),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Add datetime row
                if (entry['logTime'] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Time:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        Text(
                          entry['logTime'],
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Ground value with status
                if (entry['ground'] != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'VOL/ML: ',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            Text(
                              entry['ground'].toString(),
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                        if (statusText.isNotEmpty)
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                      ],
                    ),
                  ),

                // Battery value
                if (entry['bat'] != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        const Text(
                          'Voltage: ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${entry['bat'].toString()}V',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Update latest update card to show status
  Widget _buildLogCard(Map<String, dynamic> entry) {
    // Determine battery status and color
    final double? battery = entry['bat'];
    String batteryStatusMessage = '';
    Color batteryStatusColor = Colors.transparent;

    if (battery != null) {
      if (battery <= 3.3) {
        batteryStatusMessage = 'Please Charge your Battery';
        batteryStatusColor = Colors.red;
      }
    }

    // Get ground status
    final (groundStatusText, groundStatusColor) = _getStatusForGround(
      entry['ground'] ?? 0,
    );

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blue.shade300, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Add datetime row
            if (entry['formattedTime'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Date & Time:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    Text(
                      entry['formattedTime'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),

            // Ground value with status
            if (entry['ground'] != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'VOL/ML: ',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            Text(
                              entry['ground'].toString(),
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                        if (groundStatusText.isNotEmpty)
                          Text(
                            groundStatusText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: groundStatusColor,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

            // Battery value with status
            if (entry['bat'] != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Voltage: ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        Text(
                          '${entry['bat'].toString()}V',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                    if (batteryStatusMessage.isNotEmpty)
                      Text(
                        batteryStatusMessage,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: batteryStatusColor,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _processTimer?.cancel();
    _adapterStateSubscription?.cancel();
    _scanSubscription?.cancel();
    _deviceStateSubscription?.cancel();
    _notificationSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rentico BLE Connect'),
        actions: [
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status header
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: _status.contains("Connected")
                    ? Colors.green[100]
                    : _status.contains("Disconnected")
                    ? Colors.grey[200]
                    : Colors.blue[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Main content area
            Expanded(
              child: _connectedDevice != null
                  ? _buildConnectedUI()
                  : _buildDiscoveryUI(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveryUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Scan button
        ElevatedButton(
          onPressed: _isScanning ? null : _scanForDevices,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: Colors.blue,
            disabledBackgroundColor: Colors.blue[200],
          ),
          child: _isScanning
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text('SCANNING...', style: TextStyle(color: Colors.white)),
                  ],
                )
              : const Text(
                  'START SCANNING',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
        ),
        const SizedBox(height: 16),

        // History Page button
        ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryPage()),
            );
          },
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: const Color(0xFF002DB2),
          ),
          child: const Text(
            'VIEW HISTORY',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Device list header
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(
            _foundDevices.isEmpty
                ? 'No devices found yet'
                : 'Found ${_foundDevices.length} device(s):',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),

        // Device list
        Expanded(
          child: _foundDevices.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  itemCount: _foundDevices.length,
                  itemBuilder: (context, index) {
                    final result = _foundDevices[index];
                    final device = result.device;
                    final rssi = result.rssi;
                    final name = device.platformName.isEmpty
                        ? 'Unknown Device'
                        : device.platformName;

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const Icon(
                          Icons.bluetooth,
                          color: Colors.blue,
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ID: ${device.remoteId}'),
                            Text('RSSI: ${rssi.toString()} dBm'),
                          ],
                        ),
                        trailing:
                            _isConnecting &&
                                _connectedDevice?.remoteId == device.remoteId
                            ? const CircularProgressIndicator()
                            : ElevatedButton(
                                onPressed: () => _connectToDevice(device),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('CONNECT'),
                              ),
                        onTap: () => _connectToDevice(device),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildConnectedUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Device info
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.bluetooth_connected, color: Colors.green),
          title: Text(
            _connectedDevice?.platformName ?? 'Connected Device',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          subtitle: Text(_connectedDevice?.remoteId.toString() ?? ''),
          trailing: ElevatedButton(
            onPressed: _disconnectDevice,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('DISCONNECT'),
          ),
        ),
        const SizedBox(height: 16),

        // Command buttons
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            ActionChip(
              label: const Text('Rescan'),
              avatar: const Icon(Icons.refresh, size: 18),
              onPressed: () {
                setState(() {
                  _reloadApp();
                });
              },
            ),
            ActionChip(
              label: const Text('History'),
              avatar: const Icon(Icons.history_edu, size: 18),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HistoryPage()),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Latest Update section
        if (_latestUpdate != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Latest Update',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 8),
              _buildLogCard(_latestUpdate!),
              const SizedBox(height: 20),
            ],
          ),

        // Logs header
        const Text(
          'Device Logs: (30 minutes interval Monitoring)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        // Logs list
        Expanded(child: _buildLogListView()),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 20),
          const Text(
            'No Bluetooth Devices Found',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          Text(
            'Ensure your device is powered on and in range',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
