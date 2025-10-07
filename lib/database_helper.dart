// database_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:async';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
 

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('personal_data.db');
    return _database!;
  }

  Future<Database> _initDB(String dbName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, dbName);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,  // Now properly referenced
    );
  }

  void _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE personal_data (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        battery REAL,
        estimated_volml REAL,
        status TEXT,
        datetime TEXT
      )
    ''');

     // Create volume_val table
    await db.execute('''
      CREATE TABLE volume_val (
        id INTEGER PRIMARY KEY,
        volume INTEGER
      )
    ''');

    // Insert default row
    await _ensureVolumeRowExists(db);
  }

  // Ensures default row (id=1) exists in volume_val
  Future<void> _ensureVolumeRowExists(Database db) async {
    final result = await db.query(
      'volume_val',
      where: 'id = ?',
      whereArgs: [1],
    );
    if (result.isEmpty) {
      await db.insert('volume_val', {'id': 1, 'volume': 0});
    }
  }

  // Handles database version upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Upgrade to version 2: Add volume_val table
      await db.execute('''
        CREATE TABLE volume_val (
          id INTEGER PRIMARY KEY,
          volume INTEGER
        )
      ''');
      await _ensureVolumeRowExists(db);
    }
  }

  // Retrieves the current volume value
  Future<int> getVolumeValue() async {
    final db = await instance.database;
    final result = await db.query(
      'volume_val',
      where: 'id = ?',
      whereArgs: [1],
    );
    return result.first['volume'] as int;
  }

  // Updates the volume value
  Future<void> updateVolumeValue(int volume) async {
    final db = await instance.database;
    await db.update(
      'volume_val',
      {'volume': volume},
      where: 'id = ?',
      whereArgs: [1],
    );
  }

   Future<Map<String, int>> getVolumeStatistics(String fromDate, String toDate) async {
  final db = await database;
  
  // Get all records in date range
  final records = await db.rawQuery('''
    SELECT estimated_volml FROM personal_data 
    WHERE datetime BETWEEN ? AND ?
  ''', [fromDate, toDate]);

  // Initialize counters
  int totalBlockage = 0;
  int partiallyClosed = 0;
  int normalFlow = 0;
  int overflow = 0;
  int drainingFull = 0;

  // Count each category
  for (var record in records) {
    final dynamic value = record['estimated_volml'];
    double volml = 0.0;
    
    if (value == null) {
      volml = 0.0;
    } else if (value is num) {
      volml = value.toDouble();
    } else {
      volml = double.tryParse(value.toString()) ?? 0.0;
    }

    if (volml >= 0 && volml <= 18) {
      totalBlockage++;
    } else if (volml >= 19 && volml <= 72) {
      partiallyClosed++;
    } else if (volml >= 73 && volml <= 216) {
      normalFlow++;
    } else if (volml >= 217 && volml <= 306) {
      overflow++;
    } else if (volml >= 307) {
      drainingFull++;
    }
  }

  return {
    'Total Blockage (0 - 5)': totalBlockage,
    'Weak Flow (10 +/- 5)': partiallyClosed,
    'Normal Flow (30 +/- 5)': normalFlow,
    'High Flow (40 +/- 5)': overflow,
    'Flow/Stagnation (0 - 35)': drainingFull,
  };

}


  Future<int> insertData(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('personal_data', row);
  }

  Future<List<Map<String, dynamic>>> getDataBetweenDates(String from, String to) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT * FROM personal_data 
      WHERE datetime BETWEEN ? AND ?
      ORDER BY id DESC
    ''', [from, to]);
  }

  // Clear all data from table (keeps table structure)
  Future<int> clearAllData() async {
    final db = await instance.database;
    return await db.delete('personal_data');
  }

  // Delete entire database file
  Future<void> deleteDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'personal_data.db');
    
    // Close existing connection
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    
    // Delete file
    await databaseFactory.deleteDatabase(path);
  }

}