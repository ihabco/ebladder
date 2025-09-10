import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'database_helper.dart';
import 'history_page.dart';
import 'package:intl/intl.dart';
import 'multiplied_page.dart';

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
  //bool _isAddLogs = false;

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
  // Add this instance variable to your state class
  //DateTime _tempDateTime = DateTime.now();

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
    _loadMultiplier(); // Add this line to load the multiplier on app start
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
      // Add this instance variable to your state class
      //_tempDateTime = DateTime.now();
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
        //_status = "Scan error: ${e.toString()}";
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
            //_connectedDevice = null;
            _logCharacteristic = null;
            _cmdCharacteristic = null;
            _statusCharacteristic = null;
            //_parsedLogs.clear();
            //_logBuffer = '';
            //_latestUpdate = null;
            // Clear the list of scanned devices
            _foundDevices.clear(); // Add this line
          });
        }
      });

      await _discoverServices(device);

      // Automatically send READ_LOG command after connection
      if (_cmdCharacteristic != null) {
        await _sendCommand('READ_LOG');
      }
    } catch (e) {
      //setState(() => _status = "Connection failed: ${e.toString()}");
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

  /*  Future<void> _discoverServices(BluetoothDevice device) async {
  try {
    List<BluetoothService> services = await device.discoverServices();
    List<int> allData = []; // Create a list to accumulate all data

    for (var service in services) {
      if (service.uuid == Guid(serviceUuid)) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid == Guid(logCharUuid)) {
            _logCharacteristic = characteristic;

            // First read all available data
            List<int> data = await characteristic.read();
            allData.addAll(data); // Add the read data to the allData list

            // Then set up notifications for future updates
            await characteristic.setNotifyValue(true);
            _notificationSubscription = characteristic.lastValueStream.listen(
              (data) {
                allData.addAll(data); // Accumulate future data updates
              },
            );
          } else if (characteristic.uuid == Guid(cmdCharUuid)) {
            _cmdCharacteristic = characteristic;
          } else if (characteristic.uuid == Guid(statusCharUuid)) {
            _statusCharacteristic = characteristic;
          }
        }
      }
    }

    // Call _onDataReceived once with all accumulated data
    if (_logCharacteristic != null) {
      _onDataReceived(allData);
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
} */

  // Add this helper method to get status and color
  (String, Color) _getStatusForGround(int ground) {
    if (ground >= 0 && ground <= 18) {
      return ("Total Blockage", Colors.red);
    } else if (ground >= 19 && ground <= 72) {
      return ("Weak Flow", Colors.yellow);
    } else if (ground >= 73 && ground <= 216) {
      return ("Normal Flow", Colors.green);
    } else if (ground >= 217 && ground <= 306) {
      return ("High Flow", Colors.yellow);
    } else if (ground >= 307 && ground <= 360) {
      return ("Extreme Flow / Fault", Colors.red);
    } else {
      return ("", Colors.transparent); // For values between 50–59
    }
    /* if (ground == 0) {
      return ("Total catheter blockage", Colors.red);
    } else if (ground < 10) {
      return ("Partially Closed", Colors.orange);
    } else if (ground >= 10 && ground < 40) {
      return ("Normal Flow", Colors.blue);
    } else if (ground >= 40 && ground < 50) {
      return ("Overflow", Colors.deepPurpleAccent);
    } else if (ground >= 60) {
      return ("Draining output full / air lock", Colors.red);
    } else {
      return ("", Colors.transparent); // For values between 50–59
    } */
  }

  void _onDataReceived(List<int> data) {
    //if (!_isAddLogs) {
    try {
      String chunk = utf8.decode(data, allowMalformed: true);
      /*chunk ='[2]0,3.70\n[2]0,3.71\n[2]0,3.72\n[2]0,3.73\n[2]0,3.74\n[2]0,3.75\n[2]0,3.76\n[2]0,3.77\n';*/

      // Process all lines at once
      List<String> lines = chunk.split('\n');

      // Temporary list to hold log entries
      List<Map<String, dynamic>> validLogs = [];
      DateTime tempDateTime = DateTime.now();

      // Process lines in reverse order
      for (int i = lines.length - 1; i >= 0; i--) {
        String line = lines[i].trim();
        if (line.startsWith('[2]')) {
          line = line.substring(3);
        }
        if (line.isEmpty) continue;

        List<String> parts = line.split(',');
        if (parts.length != 2) continue;

        try {
          int ground = int.parse(parts[0].trim());
          double bat = double.parse(parts[1].trim());
          if (bat == 0.0) continue;

          int multipliedGround = ground * _volumeMultiplier;

          //tempDateTime = tempDateTime.subtract(const Duration(minutes: 30));

          var (statusText, _) = _getStatusForGround(multipliedGround);

          String logTime = DateFormat('dd-MM-yyyy').format(tempDateTime);

          String formattedTime = DateFormat(
            'dd-MM-yyyy HH:mm:ss',
          ).format(tempDateTime);

          Map<String, dynamic> parsed = {
            'ground': multipliedGround,
            'bat': bat,
            'timestamp': tempDateTime.toIso8601String(),
            'logTime': logTime, // Date only for logs
            'formattedTime': formattedTime,
            'status': statusText,
          };

          validLogs.add(parsed);
        } catch (e) {
          continue;
        }
      }

      if (validLogs.isNotEmpty) {
        setState(() {
          //_parsedLogs.clear(); // Clear previous logs
          //_parsedLogs.addAll(validLogs);
          _parsedLogs.insertAll(0, validLogs);
          // Since we processed in reverse, the first item in validLogs is actually the most recent
          _latestUpdate = {
            'ground': validLogs.first['ground'] ?? 0,
            'bat': validLogs.first['bat'],
            'formattedTime': validLogs.first['formattedTime'],
            'status': validLogs.first['status'],
          };
        });

        //_deleteDataFromDatabase();
        for (var log in validLogs.reversed) {
          _insertDataIntoDatabase(log);
        }
        _sendCommand('CLEAR_LOG');
      }
    } catch (e) {
      addToLog("FATAL ERROR: ${e.toString()}");
    }
    /*  _isAddLogs = true;
    } */
  }

  /*   Future<void> _deleteDataFromDatabase() async {
    try {
      //await _dbHelper.deleteDatabase();
      await _dbHelper.clearAllData();
    } catch (e) {
      debugPrint('Error inserting data: $e');
      setState(() => _status = "DB Error: ${e.toString()}");
    }
  } */

  Future<void> _insertDataIntoDatabase(Map<String, dynamic> parsedData) async {
    try {
      final Map<String, dynamic> row = {
        'battery': parsedData['bat'],
        'estimated_volml': parsedData['ground'],
        'status': parsedData['status'], // Use actual status text
        'datetime': parsedData['timestamp'], // Use adjusted time
      };

      await _dbHelper.insertData(row);
    } catch (e) {
      debugPrint('Error inserting data: $e');
      setState(() => _status = "DB Error: ${e.toString()}");
    }
  }

  Future<void> _sendCommand(String command) async {
    if (_cmdCharacteristic == null) return;

    try {
      await _cmdCharacteristic!.write(utf8.encode(command));
      //setState(() => _status = "Command sent: $command");
    } catch (e) {
      setState(() => _status = "Command failed: ${e.toString()}");
    }
  }

  /* Future<void> _readStatus() async {
    if (_statusCharacteristic == null) return;

    try {
      final value = await _statusCharacteristic!.read();
      setState(() => _status = "Status: ${utf8.decode(value)}");
    } catch (e) {
      setState(() => _status = "Status read failed: ${e.toString()}");
    }
  } */

  Future<void> _disconnectDevice() async {
    if (_connectedDevice != null) {
      setState(() => _status = "Disconnecting...");
      await _connectedDevice!.disconnect();
      _deviceStateSubscription?.cancel();
      _notificationSubscription?.cancel();
      setState(() {
        //_connectedDevice = null;
        _logCharacteristic = null;
        _cmdCharacteristic = null;
        _statusCharacteristic = null;
        //_parsedLogs.clear();
        //_logBuffer = '';
        //_latestUpdate = null;
        //_isAddLogs = false;
        _status = "Disconnected";
        // Clear the list of scanned devices
        _foundDevices.clear(); // Add this line
      });
    }
  }

  Future<void> _reloadApp() async {
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
        //_isAddLogs = false;
        _latestUpdate = null;
        _status = "Disconnected";
        // Clear the list of scanned devices
        _foundDevices.clear(); // Add this line
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
                              'Estimated Hits Sensing: ',
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
                          'Battery: ',
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
      /* if (battery <= 3) {
        batteryStatusMessage = 'Less than 50% Battery';
        batteryStatusColor = Colors.deepOrange;
      } else if (battery <= 2.7) {
        batteryStatusMessage = 'Please Charge the device';
        batteryStatusColor = Colors.red;
      } else if (battery > 2.7) {
        batteryStatusMessage = 'Battery in good condition';
        batteryStatusColor = Colors.green;
      } */
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
                              'Estimated Hits Sensing: ',
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
                          'Battery: ',
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

        // NEW: History Page button
        ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryPage()),
            );
          },
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: const Color(0xFF002DB2), // Hexadecimal color
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
            /*ActionChip(
              label: const Text('Read Log'),
              avatar: const Icon(Icons.download, size: 18),
              onPressed: () => _sendCommand('READ_LOG'),
            ),
           ActionChip(
              label: const Text('Clear Log'),
              avatar: const Icon(Icons.clear, size: 18),
              onPressed: () => _sendCommand('CLEAR_LOG'),
            ),
            ActionChip(
              label: const Text('Read Status'),
              avatar: const Icon(Icons.info, size: 18),
              onPressed: _readStatus,
            ),
             ActionChip(
              label: const Text('Clear Display'),
              avatar: const Icon(Icons.delete_sweep, size: 18),
              onPressed: () {
                setState(() {
                  _parsedLogs.clear();
                  _latestUpdate = null;
                });
              },
            ), */
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
            ActionChip(
              label: const Text('Multiplied value'),
              avatar: const Icon(Icons.numbers, size: 18),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MultipliedPage()),
                );
                _loadMultiplier(); // Reload after returning
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

        // Logs list - Now in chronological order
        Expanded(child: _buildLogListView()),

        /*  SizedBox(height: 20),
        Expanded(
          child: ListView.builder(
            itemCount: logMessages.length,
            itemBuilder: (context, index) {
              return Text(logMessages[index]);
            },
          ),
        ),  */
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
