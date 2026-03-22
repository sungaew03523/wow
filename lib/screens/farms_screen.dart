import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:function_tree/function_tree.dart';

import '../blizzard_api_service.dart';
import '../models/auction_item.dart';

// --- Модель данных для фарма ---
class Farm {
  final String id;
  final String name;
  final String profession;
  final String formula;
  final int craftsCount;
  final Timestamp createdAt;

  Farm({
    required this.id,
    required this.name,
    required this.profession,
    required this.formula,
    required this.craftsCount,
    required this.createdAt,
  });

  factory Farm.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data()! as Map<String, dynamic>;
    return Farm(
      id: doc.id,
      name: data['name'] ?? 'Без названия',
      profession: data['profession'] ?? 'Нет профессии',
      formula: data['formula'] ?? '',
      craftsCount: data['craftsCount'] as int? ?? 1,
      createdAt: data['createdAt'] ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'profession': profession,
      'formula': formula,
      'craftsCount': craftsCount,
      'createdAt': createdAt,
    };
  }
}

class FarmsScreen extends StatefulWidget {
  const FarmsScreen({super.key});

  @override
  State<FarmsScreen> createState() => _FarmsScreenState();
}

class _FarmsScreenState extends State<FarmsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Key _listViewKey = UniqueKey();
  bool _isPriceUpdating = false;
  // Хранит ручные переопределения цен: {farmId: {itemName: manualPrice}}
  final Map<String, Map<String, double>> _priceOverrides = {};

  final List<String> _professions = [
    'Алхимия',
    'Кузнечное дело',
    'Наложение чар',
    'Инженерное дело',
    'Начертание',
    'Ювелирное дело',
    'Кожевничество',
    'Портняжное дело',
  ];

  Future<void> _showFarmDialog({Farm? farm}) async {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final TextEditingController nameController = TextEditingController(
      text: farm?.name,
    );
    final TextEditingController formulaController = TextEditingController(
      text: farm?.formula,
    );
    final TextEditingController craftsController = TextEditingController(
      text: farm?.craftsCount.toString() ?? '1',
    );
    String? selectedProfession = farm?.profession;
    AuctionItem? selectedFavorite;

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                farm == null ? 'Добавить новый фарм' : 'Редактировать фарм',
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextFormField(
                        controller: craftsController,
                        decoration: const InputDecoration(
                          labelText: 'Количество крафтов',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Введите количество';
                          }
                          if (int.tryParse(value) == null) {
                            return 'Введите число';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedProfession,
                        decoration: const InputDecoration(
                          labelText: 'Профессия',
                          border: OutlineInputBorder(),
                        ),
                        items: _professions.map((String profession) {
                          return DropdownMenuItem<String>(
                            value: profession,
                            child: Text(profession),
                          );
                        }).toList(),
                        onChanged: (newValue) {
                          selectedProfession = newValue;
                        },
                        validator: (value) =>
                            value == null ? 'Выберите профессию' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Название фарма',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Введите название'
                            : null,
                      ),
                      const SizedBox(height: 20),
                      StreamBuilder<QuerySnapshot>(
                        stream: _firestore.collection('favorites').snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const CircularProgressIndicator();
                          }
                          final favoriteItems = snapshot.data!.docs
                              .map((doc) => AuctionItem.fromFirestore(doc))
                              .toList();
                          if (favoriteItems.isEmpty) {
                            return const Text('Нет избранных предметов.');
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<AuctionItem>(
                                  decoration: const InputDecoration(
                                    labelText: 'Избранное',
                                    border: OutlineInputBorder(),
                                  ),
                                  initialValue: selectedFavorite,
                                  items: favoriteItems.map((AuctionItem item) {
                                    return DropdownMenuItem<AuctionItem>(
                                      value: item,
                                      child: Text(
                                        item.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (item) {
                                    setState(() => selectedFavorite = item);
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: TextButton(
                                  child: const Text('Добавить'),
                                  onPressed: () {
                                    if (selectedFavorite != null) {
                                      final itemNameToAdd =
                                          '"${selectedFavorite!.name}"';
                                      final currentText =
                                          formulaController.text;
                                      final currentSelection =
                                          formulaController.selection;
                                      final newText = currentText.replaceRange(
                                        currentSelection.start,
                                        currentSelection.end,
                                        itemNameToAdd,
                                      );
                                      formulaController.value =
                                          TextEditingValue(
                                        text: newText,
                                        selection: TextSelection.collapsed(
                                          offset: currentSelection.start +
                                              itemNameToAdd.length,
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: formulaController,
                        decoration: const InputDecoration(
                          labelText: 'Формула',
                          hintText: 'Пример: 2*"Предмет1" - 1*"Предмет2"',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                        validator: (value) => value == null || value.isEmpty
                            ? 'Введите формулу'
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Отмена'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  child: Text(farm == null ? 'Добавить' : 'Сохранить'),
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      final int craftsCount = int.parse(craftsController.text);
                      if (farm == null) {
                        _addFarm(
                          nameController.text,
                          selectedProfession!,
                          formulaController.text,
                          craftsCount,
                        );
                      } else {
                        _updateFarm(
                          farm.id,
                          nameController.text,
                          selectedProfession!,
                          formulaController.text,
                          craftsCount,
                        );
                      }
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addFarm(
    String name,
    String profession,
    String formula,
    int craftsCount,
  ) async {
    try {
      await _firestore.collection('farms').add({
        'name': name,
        'profession': profession,
        'formula': formula,
        'craftsCount': craftsCount,
        'createdAt': Timestamp.now(),
      });
    } catch (e) {
      _showErrorSnackBar('Ошибка при добавлении фарма: $e');
    }
  }

  Future<void> _updateFarm(
    String id,
    String name,
    String profession,
    String formula,
    int craftsCount,
  ) async {
    try {
      await _firestore.collection('farms').doc(id).update({
        'name': name,
        'profession': profession,
        'formula': formula,
        'craftsCount': craftsCount,
      });
    } catch (e) {
      _showErrorSnackBar('Ошибка при обновлении фарма: $e');
    }
  }

  Future<void> _duplicateFarm(Farm farm) async {
    try {
      await _addFarm(
        '${farm.name} (копия)',
        farm.profession,
        farm.formula,
        farm.craftsCount,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Фарм успешно дублирован.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showErrorSnackBar('Ошибка при дублировании фарма: $e');
    }
  }

  Future<void> _deleteFarm(String farmId) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Подтверждение удаления'),
          content: const Text('Вы уверены, что хотите удалить этот фарм?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'Удалить',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await _firestore.collection('farms').doc(farmId).delete();
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Фарм успешно удален.'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        if (!mounted) {
          return;
        }
        _showErrorSnackBar('Ошибка при удалении фарма: $e');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _refreshFarms() {
    setState(() {
      _listViewKey = UniqueKey();
    });
  }

  Future<void> _handleFullUpdate() async {
    setState(() => _isPriceUpdating = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Text('Обновление цен началось...'),
        backgroundColor: Colors.blue,
      ),
    );

    try {
      final favoritesSnapshot = await _firestore.collection('favorites').get();
      final itemsToUpdate = {
        for (var doc in favoritesSnapshot.docs)
          doc.id: (doc.data()['analysisVolume'] ?? 1000) as int,
      };

      if (itemsToUpdate.isEmpty) {
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Нет избранных предметов для обновления.'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        await BlizzardApiService().fetchReagentPrices(itemsToUpdate);
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Цены успешно обновлены!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Ошибка при обновлении цен: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPriceUpdating = false;
        });
        _refreshFarms();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF1E3A8A),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      textStyle: const TextStyle(fontSize: 14),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Фармы'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          tooltip: 'На главную',
          onPressed: () => context.go('/'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: _isPriceUpdating
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _handleFullUpdate,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Обновить цены'),
                    style: buttonStyle,
                  ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('favorites').snapshots(),
        builder: (context, favoritesSnapshot) {
          if (favoritesSnapshot.hasError) {
            return const Center(child: Text('Ошибка загрузки цен'));
          }
          if (favoritesSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final favoritesMap = {
            for (var doc in favoritesSnapshot.data!.docs)
              (doc.data() as Map<String, dynamic>)['name'] as String:
                  AuctionItem.fromFirestore(doc)
          };

          return StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('farms')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Что-то пошло не так'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final farmDocs = snapshot.data?.docs ?? [];
              if (farmDocs.isEmpty) {
                return const Center(
                  child: Text(
                    'Пока нет ни одного фарма. Нажмите "+", чтобы добавить.',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                );
              }

              return ListView.builder(
                key: _listViewKey,
                padding: const EdgeInsets.all(8.0),
                itemCount: farmDocs.length,
                itemBuilder: (context, index) {
                  final farm = Farm.fromFirestore(farmDocs[index]);
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      vertical: 8.0,
                      horizontal: 4.0,
                    ),
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withAlpha(128),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  farm.name,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.copy_outlined,
                                  color: Colors.green,
                                ),
                                tooltip: 'Дублировать',
                                onPressed: () => _duplicateFarm(farm),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  color: Colors.blue,
                                ),
                                tooltip: 'Редактировать',
                                onPressed: () => _showFarmDialog(farm: farm),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                ),
                                tooltip: 'Удалить',
                                onPressed: () => _deleteFarm(farm.id),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            farm.profession,
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Формула: ${farm.formula}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Количество крафтов: ${farm.craftsCount}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const Divider(),
                          FarmComponentsList(
                            formula: farm.formula,
                            favorites: favoritesMap,
                            overrides: _priceOverrides[farm.id] ?? {},
                            onOverrideChanged: (itemName, newPrice) {
                              setState(() {
                                if (newPrice == null) {
                                  _priceOverrides[farm.id]?.remove(itemName);
                                } else {
                                  _priceOverrides[farm.id] ??= {};
                                  _priceOverrides[farm.id]![itemName] =
                                      newPrice;
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          FarmProfitCalculator(
                            formula: farm.formula,
                            favorites: favoritesMap,
                            craftsCount: farm.craftsCount,
                            overrides: _priceOverrides[farm.id] ?? {},
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFarmDialog(),
        tooltip: 'Добавить фарм',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// --- Виджет для расчета прибыли ---
class FarmProfitCalculator extends StatelessWidget {
  final String formula;
  final int craftsCount;
  final Map<String, AuctionItem> favorites;
  final Map<String, double> overrides;

  const FarmProfitCalculator({
    super.key,
    required this.formula,
    required this.craftsCount,
    required this.favorites,
    required this.overrides,
  });

  @override
  Widget build(BuildContext context) {
    if (formula.trim().isEmpty) return const SizedBox.shrink();

    final itemNames = _extractItemNames(formula);

    // Подготовка цен из переданной мапы favorites
    final Map<String, double> effectivePrices = {};
    for (String name in itemNames) {
      if (overrides.containsKey(name)) {
        effectivePrices[name] = overrides[name]!;
      } else {
        effectivePrices[name] = favorites[name]?.weightedAveragePrice ?? 0.0;
      }
    }

    String formulaWithPrices = formula;
    for (String name in itemNames) {
      formulaWithPrices = formulaWithPrices.replaceAll(
          '"$name"', effectivePrices[name]?.toString() ?? '0');
    }

    if (formulaWithPrices.trim().isEmpty) return const SizedBox.shrink();

    double profit = 0;
    String? error;
    try {
      profit = formulaWithPrices.interpret().toDouble();
    } catch (e) {
      error = e.toString();
      debugPrint('Ошибка вычисления формулы ($formulaWithPrices): $e');
    }

    if (error != null) {
      return Tooltip(
          message: error,
          child: Text('Прибыль за крафт: Ошибка',
              style: TextStyle(color: Colors.orange.shade800)));
    }

    return Text(
      'Прибыль за крафт: ${profit.toStringAsFixed(2)} з',
      style: TextStyle(
          color: profit > 0 ? Colors.green.shade600 : Colors.red.shade600,
          fontWeight: FontWeight.bold,
          fontSize: 16),
    );
  }

  Set<String> _extractItemNames(String formula) {
    final RegExp regex = RegExp(r'"([^"]+)"');
    return regex.allMatches(formula).map((m) => m.group(1)!).toSet();
  }
}

// --- КОМПАКТНЫЙ ВИДЖЕТ ДЛЯ ОТОБРАЖЕНИЯ КОМПОНЕНТОВ ---
class FarmComponentsList extends StatelessWidget {
  final String formula;
  final Map<String, AuctionItem> favorites;
  final Map<String, double> overrides;
  final Function(String itemName, double? newPrice) onOverrideChanged;

  const FarmComponentsList({
    super.key,
    required this.formula,
    required this.favorites,
    required this.overrides,
    required this.onOverrideChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (formula.trim().isEmpty) return const SizedBox.shrink();

    final RegExp nameRegex = RegExp(r'"([^"]+)"');
    final allItemNames =
        nameRegex.allMatches(formula).map((m) => m.group(1)!).toSet();

    if (allItemNames.isEmpty) return const SizedBox.shrink();

    final List<Map<String, dynamic>> components = [];
    for (final name in allItemNames) {
      final itemData = favorites[name];
      components.add({
        'name': name,
        'price': itemData?.weightedAveragePrice ?? 0.0,
        'iconUrl': itemData?.iconUrl,
      });
    }
    components.sort((a, b) => a['name'].compareTo(b['name']));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
          child: Text('Компоненты:',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontSize: 16)),
        ),
        Wrap(
          spacing: 12.0,
          runSpacing: 6.0,
          children: components.map((component) {
            final String name = component['name'];
            final bool isOverridden = overrides.containsKey(name);
            final double pricePerPiece =
                isOverridden ? overrides[name]! : component['price'];

            return InkWell(
              onTap: () async {
                final TextEditingController controller = TextEditingController(
                  text: pricePerPiece.toStringAsFixed(2),
                );
                final double? result = await showDialog<double>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Цена для "$name"'),
                    content: TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'Цена за 1 шт.',
                        suffixText: 'з',
                      ),
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true),
                      autofocus: true,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Отмена'),
                      ),
                      if (isOverridden)
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(context, -1.0), // Сигнал сброса
                          child: const Text('Сброс',
                              style: TextStyle(color: Colors.orange)),
                        ),
                      ElevatedButton(
                        onPressed: () {
                          final val = double.tryParse(
                              controller.text.replaceAll(',', '.'));
                          Navigator.pop(context, val);
                        },
                        child: const Text('Применить'),
                      ),
                    ],
                  ),
                );

                if (result != null) {
                  if (result < 0) {
                    onOverrideChanged(name, null);
                  } else {
                    onOverrideChanged(name, result);
                  }
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: Chip(
                backgroundColor:
                    isOverridden ? Colors.blue.withAlpha(40) : null,
                side: isOverridden
                    ? const BorderSide(color: Colors.blue, width: 1)
                    : null,
                avatar: CircleAvatar(
                  radius: 11,
                  backgroundColor: Colors.transparent,
                  child: component['iconUrl'] != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(3.0),
                          child: Image.network(
                            component['iconUrl']!,
                            width: 22,
                            height: 22,
                            fit: BoxFit.cover,
                            errorBuilder: (c, o, s) =>
                                const Icon(Icons.inventory_2, size: 12),
                          ),
                        )
                      : const Icon(Icons.inventory_2, size: 12),
                ),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$name: ${pricePerPiece.toStringAsFixed(2)} з'),
                    if (isOverridden)
                      const Padding(
                        padding: EdgeInsets.only(left: 4.0),
                        child:
                            Icon(Icons.edit_note, size: 14, color: Colors.blue),
                      ),
                  ],
                ),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      isOverridden ? FontWeight.bold : FontWeight.normal,
                  color: isOverridden ? Colors.blue.shade800 : null,
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity:
                    const VisualDensity(horizontal: 0.0, vertical: -2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
