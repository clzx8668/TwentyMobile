import 'dart:convert';

enum OutboxEntityType { contact, company, note, task }

enum OutboxOperation { create, update, delete }

enum OutboxStatus { pending, processing, failed, conflict }

class OutboxItem {
  OutboxItem({
    required this.operationId,
    required this.entityType,
    required this.operation,
    required this.payload,
    required this.createdAt,
    this.entityId,
    this.status = OutboxStatus.pending,
    this.retryCount = 0,
    this.lastAttemptAt,
    this.lastError,
  });

  final String operationId;
  final OutboxEntityType entityType;
  final OutboxOperation operation;
  final String? entityId;
  final Map<String, dynamic> payload;
  final OutboxStatus status;
  final int retryCount;
  final DateTime createdAt;
  final DateTime? lastAttemptAt;
  final String? lastError;

  OutboxItem copyWith({
    String? operationId,
    OutboxEntityType? entityType,
    OutboxOperation? operation,
    String? entityId,
    Map<String, dynamic>? payload,
    OutboxStatus? status,
    int? retryCount,
    DateTime? createdAt,
    DateTime? lastAttemptAt,
    String? lastError,
  }) {
    return OutboxItem(
      operationId: operationId ?? this.operationId,
      entityType: entityType ?? this.entityType,
      operation: operation ?? this.operation,
      entityId: entityId ?? this.entityId,
      payload: payload ?? this.payload,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'operationId': operationId,
      'entityType': entityType.name,
      'operation': operation.name,
      'entityId': entityId,
      'payload': payload,
      'status': status.name,
      'retryCount': retryCount,
      'createdAt': createdAt.toIso8601String(),
      'lastAttemptAt': lastAttemptAt?.toIso8601String(),
      'lastError': lastError,
    };
  }

  static OutboxItem fromJson(Map<String, dynamic> json) {
    final statusRaw = (json['status'] as String?) ?? OutboxStatus.pending.name;
    OutboxStatus status;
    try {
      status = OutboxStatus.values.byName(statusRaw);
    } catch (_) {
      status = OutboxStatus.pending;
    }

    return OutboxItem(
      operationId: json['operationId'] as String,
      entityType: OutboxEntityType.values.byName(json['entityType'] as String),
      operation: OutboxOperation.values.byName(json['operation'] as String),
      entityId: json['entityId'] as String?,
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      status: status,
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastAttemptAt: json['lastAttemptAt'] != null
          ? DateTime.parse(json['lastAttemptAt'] as String)
          : null,
      lastError: json['lastError'] as String?,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static OutboxItem fromJsonString(String raw) {
    final decoded = jsonDecode(raw);
    return OutboxItem.fromJson(Map<String, dynamic>.from(decoded as Map));
  }
}
