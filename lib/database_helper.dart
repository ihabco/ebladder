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
      version: 3, // Incremented version
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
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
    if (oldVersion < 3) {
      // You can add future migrations here
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

  // Check if datetime already exists
  Future<bool> doesDateTimeExist(String datetime) async {
    final db = await instance.database;
    final result = await db.query(
      'personal_data',
      where: 'datetime = ?',
      whereArgs: [datetime],
    );
    return result.isNotEmpty;
  }

  Future<int> insertData(Map<String, dynamic> row) async {
    final db = await instance.database;
    final String datetime = row['datetime']?.toString() ?? '';

    // Check if datetime already exists
    final bool exists = await doesDateTimeExist(datetime);
    if (exists) {
      return 0;
    } else {
      return await db.insert('personal_data', row);
    }
  }

  Future<List<Map<String, dynamic>>> getDataBetweenDates(
    String from,
    String to,
  ) async {
    final db = await instance.database;
    return await db.rawQuery(
      '''
      SELECT * FROM personal_data 
      WHERE datetime BETWEEN ? AND ?
      ORDER BY id DESC
    ''',
      [from, to],
    );
  }

  Future<List<Map<String, dynamic>>> srchDataBetweenDates(
    String from,
    String to,
  ) async {
    final db = await instance.database;
    
    
    try {
      final results = await db.rawQuery(
        '''
        SELECT * FROM personal_data 
        WHERE datetime >= ? AND datetime <= ?
        ORDER BY 
          substr(datetime, 7, 4) || '-' ||  -- year
          substr(datetime, 4, 2) || '-' ||  -- month  
          substr(datetime, 1, 2) || ' ' ||  -- day
          substr(datetime, 12) DESC         -- time
        ''',
        [from, to],
      );

    
      return results;
    } catch (e) {
     
      return [];
    }
  }

  // Alternative simpler method that might work better
  Future<List<Map<String, dynamic>>> searchByDateTimeRange(
    String from,
    String to,
  ) async {
    final db = await instance.database;
    
   

    try {
     
  
      final results = await db.rawQuery(
        '''
        SELECT * FROM personal_data 
        WHERE datetime BETWEEN ? AND ?
        ORDER BY datetime DESC
        ''',
        [from, to],
      );

     
      return results;
    } catch (e) {
    
      return [];
    }
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