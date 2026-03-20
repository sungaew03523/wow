import 'package:cloud_firestore/cloud_firestore.dart';

class RecipeReagent {
  final int itemId;
  final String name;
  final int quantity;

  RecipeReagent({
    required this.itemId,
    required this.name,
    required this.quantity,
  });

  factory RecipeReagent.fromMap(Map<String, dynamic> map) {
    return RecipeReagent(
      itemId: map['itemId'] as int? ?? 0,
      name: map['name'] as String? ?? 'Неизвестный реагент',
      quantity: map['quantity'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'itemId': itemId,
      'name': name,
      'quantity': quantity,
    };
  }
}

class WowRecipe {
  final int id;
  final String name;
  final String? iconUrl;
  final int? craftedItemId;
  final int? craftedQuantity;
  final List<RecipeReagent> reagents;
  final String? professionName;

  WowRecipe({
    required this.id,
    required this.name,
    this.iconUrl,
    this.craftedItemId,
    this.craftedQuantity,
    this.reagents = const [],
    this.professionName,
  });

  factory WowRecipe.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data()! as Map<String, dynamic>;
    var reagentsRaw = data['reagents'] as List<dynamic>? ?? [];

    return WowRecipe(
      id: data['id'] ?? 0,
      name: data['name'] ?? 'Без имени',
      iconUrl: data['iconUrl'],
      craftedItemId: data['craftedItemId'] as int?,
      craftedQuantity: data['craftedQuantity'] as int?,
      reagents: reagentsRaw
          .map((r) => RecipeReagent.fromMap(r as Map<String, dynamic>))
          .toList(),
      professionName: data['professionName'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      if (iconUrl != null) 'iconUrl': iconUrl,
      if (craftedItemId != null) 'craftedItemId': craftedItemId,
      if (craftedQuantity != null) 'craftedQuantity': craftedQuantity,
      'reagents': reagents.map((r) => r.toMap()).toList(),
      if (professionName != null) 'professionName': professionName,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WowRecipe && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
