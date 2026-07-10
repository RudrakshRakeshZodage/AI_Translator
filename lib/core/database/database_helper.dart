import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/models.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'translator_sessions.db');
    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sessions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            createdAt TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE messages(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sessionId INTEGER,
            speakerId INTEGER,
            originalText TEXT,
            translatedText TEXT,
            timestamp TEXT,
            FOREIGN KEY (sessionId) REFERENCES sessions (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE eth_transactions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            fromAddress TEXT,
            toAddress TEXT,
            amount TEXT,
            timestamp TEXT,
            status TEXT,
            txHash TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE eth_transactions(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              fromAddress TEXT,
              toAddress TEXT,
              amount TEXT,
              timestamp TEXT,
              status TEXT,
              txHash TEXT
            )
          ''');
        }
      },
    );
  }

  // Session Methods
  Future<int> createSession(String title) async {
    final db = await database;
    return await db.insert('sessions', TranslationSession(
      title: title,
      createdAt: DateTime.now(),
    ).toMap());
  }

  Future<List<TranslationSession>> getSessions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('sessions', orderBy: 'createdAt DESC');
    return List.generate(maps.length, (i) => TranslationSession.fromMap(maps[i]));
  }

  // Message Methods
  Future<void> addMessage(TranslationMessage message) async {
    final db = await database;
    await db.insert('messages', message.toMap());
  }

  Future<List<TranslationMessage>> getMessagesForSession(int sessionId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'sessionId = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
    return List.generate(maps.length, (i) => TranslationMessage.fromMap(maps[i]));
  }

  Future<void> deleteSession(int id) async {
    final db = await database;
    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
  }

  // Ethereum Transaction Methods
  Future<int> addEthTransaction(EthTransaction tx) async {
    final db = await database;
    return await db.insert('eth_transactions', tx.toMap());
  }

  Future<List<EthTransaction>> getEthTransactions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('eth_transactions', orderBy: 'timestamp DESC');
    return List.generate(maps.length, (i) => EthTransaction.fromMap(maps[i]));
  }

  Future<void> updateEthTransaction(EthTransaction tx) async {
    final db = await database;
    await db.update(
      'eth_transactions',
      tx.toMap(),
      where: 'id = ?',
      whereArgs: [tx.id],
    );
  }
}
