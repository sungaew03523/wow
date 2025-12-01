import 'package:cloud_firestore/cloud_firestore.dart';

// --- Модель данных для предмета на аукционе ---
class AuctionItem {
  final int id;
  final String name;
  final String? iconUrl;
  final double? minimalCost;
  final double? averageCost;
  final Map<String, dynamic>? averagePriceHistory;

  AuctionItem({
    required this.id,
    required this.name,
    this.iconUrl,
    this.minimalCost,
    this.averageCost,
    this.averagePriceHistory,
  });

  factory AuctionItem.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data()! as Map<String, dynamic>;
    return AuctionItem(
      id: data['id'] ?? 0,
      name: data['name'] ?? 'Без имени',
      iconUrl: data['iconUrl'],
      minimalCost: (data['minimalCost'] as num?)?.toDouble(),
      averageCost: (data['averageCost'] as num?)?.toDouble(),
      averagePriceHistory: data['averagePriceHistory'] != null
          ? Map<String, dynamic>.from(data['averagePriceHistory'])
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'iconUrl': iconUrl,
      if (minimalCost != null) 'minimalCost': minimalCost,
      if (averageCost != null) 'averageCost': averageCost,
      if (averagePriceHistory != null)
        'averagePriceHistory': averagePriceHistory,
    };
  }

  // Добавляем эти методы для корректного сравнения объектов
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuctionItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
