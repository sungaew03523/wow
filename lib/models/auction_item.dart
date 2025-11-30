
import 'package:cloud_firestore/cloud_firestore.dart';

// --- Модель данных для предмета ---
class AuctionItem {
  final int id;
  final String name;
  final String? iconUrl;
  final double? minimalCost;
  final double? averageCost;
  final int itemLevel; // Уровень предмета (1, 2 или 3)

  AuctionItem({
    required this.id,
    required this.name,
    this.iconUrl,
    this.minimalCost,
    this.averageCost,
    this.itemLevel = 1, // Значение по умолчанию
  });

  factory AuctionItem.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data()! as Map<String, dynamic>;
    return AuctionItem(
      id: data['id'] ?? 0,
      name: data['name'] ?? 'Без имени',
      iconUrl: data['iconUrl'],
      minimalCost: (data['minimalCost'] as num?)?.toDouble(),
      averageCost: (data['averageCost'] as num?)?.toDouble(),
      itemLevel: data['itemLevel'] ?? 1, // Загружаем уровень, по умолчанию 1
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'iconUrl': iconUrl,
      'itemLevel': itemLevel, // Сохраняем уровень
      if (minimalCost != null) 'minimalCost': minimalCost,
      if (averageCost != null) 'averageCost': averageCost,
    };
  }
}
