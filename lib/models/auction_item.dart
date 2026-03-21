import 'package:cloud_firestore/cloud_firestore.dart';

// --- Модель данных для предмета на аукционе ---
class AuctionItem {
  final int id;
  final String name;
  final String? iconUrl;
  final double? minimalCost;
  final double? marketPrice; // Цена стены
  final double? weightedAveragePrice; // Средневзвешенная цена
  final Map<String, dynamic>? averagePriceHistory;
  final Map<String, dynamic>? totalQuantityHistory;
  final int analysisVolume;
  final List<String> professions;

  AuctionItem({
    required this.id,
    required this.name,
    this.iconUrl,
    this.minimalCost,
    this.marketPrice,
    this.weightedAveragePrice,
    this.averagePriceHistory,
    this.totalQuantityHistory,
    this.analysisVolume = 1000,
    this.professions = const [],
  });

  factory AuctionItem.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data()! as Map<String, dynamic>;
    return AuctionItem(
      id: data['id'] ?? 0,
      name: data['name'] ?? 'Без имени',
      iconUrl: data['iconUrl'],
      minimalCost: (data['minimalCost'] as num?)?.toDouble(),
      marketPrice: (data['marketPrice'] as num?)?.toDouble(),
      weightedAveragePrice: (data['weightedAveragePrice'] as num?)?.toDouble(),
      averagePriceHistory: data['averagePriceHistory'] != null
          ? Map<String, dynamic>.from(data['averagePriceHistory'])
          : null,
      totalQuantityHistory: data['totalQuantityHistory'] != null
          ? Map<String, dynamic>.from(data['totalQuantityHistory'])
          : null,
      analysisVolume: data['analysisVolume'] ?? 1000,
      professions: List<String>.from(data['professions'] ?? []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'iconUrl': iconUrl,
      'analysisVolume': analysisVolume,
      'professions': professions,
      if (minimalCost != null) 'minimalCost': minimalCost,
      if (marketPrice != null) 'marketPrice': marketPrice,
      if (weightedAveragePrice != null)
        'weightedAveragePrice': weightedAveragePrice,
      if (averagePriceHistory != null)
        'averagePriceHistory': averagePriceHistory,
      if (totalQuantityHistory != null)
        'totalQuantityHistory': totalQuantityHistory,
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
