import 'dart:convert';

class TranslationMessage {
  final int? id;
  final int sessionId;
  final int speakerId;
  final String originalText;
  final String translatedText;
  final DateTime timestamp;

  TranslationMessage({
    this.id,
    required this.sessionId,
    required this.speakerId,
    required this.originalText,
    required this.translatedText,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sessionId': sessionId,
      'speakerId': speakerId,
      'originalText': originalText,
      'translatedText': translatedText,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory TranslationMessage.fromMap(Map<String, dynamic> map) {
    return TranslationMessage(
      id: map['id'],
      sessionId: map['sessionId'],
      speakerId: map['speakerId'],
      originalText: map['originalText'],
      translatedText: map['translatedText'],
      timestamp: DateTime.parse(map['timestamp']),
    );
  }
}

class TranslationSession {
  final int? id;
  final String title;
  final DateTime createdAt;

  TranslationSession({
    this.id,
    required this.title,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory TranslationSession.fromMap(Map<String, dynamic> map) {
    return TranslationSession(
      id: map['id'],
      title: map['title'],
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}

class StellarTransaction {
  final int? id;
  final String fromAddress;
  final String toAddress;
  final String amount;
  final String assetCode; // 'XLM' or 'TranslateCredits'
  final DateTime timestamp;
  final String status; // 'Pending Sync', 'Completed', 'Failed'
  final String? txHash;

  StellarTransaction({
    this.id,
    required this.fromAddress,
    required this.toAddress,
    required this.amount,
    required this.assetCode,
    required this.timestamp,
    required this.status,
    this.txHash,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fromAddress': fromAddress,
      'toAddress': toAddress,
      'amount': amount,
      'assetCode': assetCode,
      'timestamp': timestamp.toIso8601String(),
      'status': status,
      'txHash': txHash,
    };
  }

  factory StellarTransaction.fromMap(Map<String, dynamic> map) {
    return StellarTransaction(
      id: map['id'],
      fromAddress: map['fromAddress'] ?? '',
      toAddress: map['toAddress'] ?? '',
      amount: map['amount'] ?? '',
      assetCode: map['assetCode'] ?? 'XLM',
      timestamp: DateTime.parse(map['timestamp']),
      status: map['status'] ?? '',
      txHash: map['txHash'],
    );
  }
}

