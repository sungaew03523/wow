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
  int _countForAverage = 10; // Значение по умолчанию

  final List<String> _professions = [
    'Алхимия',
    'Кузнечное дело',
    'Наложение чар',
    'Инженерное дело',
    'Травничество',
    'Начертание',
    'Ювелирное дело',
    'Кожевничество',
    'Портняжное дело',
    'Горное дело',
    'Снятие шкур',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await _firestore
          .collection('settings')
          .doc('user_settings')
          .get();
      if (doc.exists && doc.data()!.containsKey('countForAverage')) {
        if (mounted) {
          setState(() {
            _countForAverage = doc.data()!['countForAverage'];
          });
        }
      }
    } catch (e) {
      print("Ошибка загрузки настроек: $e");
    }
  }

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
                                              offset:
                                                  currentSelection.start +
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Обновление цен началось...'),
          backgroundColor: Colors.blue,
        ),
      );
    }

    try {
      final favoriteIds = (await _firestore.collection('favorites').get()).docs
          .map((doc) => doc.id)
          .toList();

      if (favoriteIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Нет избранных предметов для обновления.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      await BlizzardApiService().fetchReagentPrices(
        _countForAverage,
        favoriteIds,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Цены успешно обновлены!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      _refreshFarms();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при обновлении цен: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPriceUpdating = false);
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
      ), // Уменьшенный padding для AppBar
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
                    color: Theme.of(context).colorScheme.outline.withAlpha(128),
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
                      FarmProfitCalculator(formula: farm.formula),
                    ],
                  ),
                ),
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

// --- Виджет для расчета и отображения прибыли ---
class FarmProfitCalculator extends StatefulWidget {
  final String formula;

  const FarmProfitCalculator({super.key, required this.formula});

  @override
  State<FarmProfitCalculator> createState() => _FarmProfitCalculatorState();
}

class _FarmProfitCalculatorState extends State<FarmProfitCalculator> {
  late Future<double> _profitFuture;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _profitFuture = _calculateProfit();
  }

  @override
  void didUpdateWidget(covariant FarmProfitCalculator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.formula != widget.formula) {
      setState(() {
        _profitFuture = _calculateProfit();
      });
    }
  }

  Set<String> _extractItemNames(String formula) {
    final RegExp regex = RegExp(r'"([^"]+)"');
    return regex.allMatches(formula).map((m) => m.group(1)!).toSet();
  }

  Future<Map<String, double>> _getItemPricesFromFirestore(
    Set<String> itemNames,
  ) async {
    if (itemNames.isEmpty) {
      return {};
    }

    final Map<String, double> prices = {};
    final List<String> namesList = itemNames.toList();
    for (var i = 0; i < namesList.length; i += 30) {
      final chunk = namesList.sublist(
        i,
        i + 30 > namesList.length ? namesList.length : i + 30,
      );
      final querySnapshot = await _firestore
          .collection('favorites')
          .where('name', whereIn: chunk)
          .get();

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final name = data['name'] as String?;
        final avgCost = (data['averageCost'] as num?)?.toDouble();
        if (name != null && avgCost != null) {
          prices[name] = avgCost;
        }
      }
    }
    return prices;
  }

  Future<double> _calculateProfit() async {
    if (widget.formula.isEmpty) {
      return 0.0;
    }

    final itemNamesInFormula = _extractItemNames(widget.formula);

    if (itemNamesInFormula.isEmpty) {
      try {
        final result = widget.formula.interpret();
        return (result).toDouble();
      } catch (e) {
        throw Exception(
          'Формула не содержит предметов и не является валидным математическим выражением.',
        );
      }
    }

    final Map<String, double> itemPrices = await _getItemPricesFromFirestore(
      itemNamesInFormula,
    );

    String formulaWithPrices = widget.formula;
    for (String name in itemNamesInFormula) {
      final double price = itemPrices[name] ?? 0.0;
      formulaWithPrices = formulaWithPrices.replaceAll(
        '"$name"',
        price.toString(),
      );
    }

    try {
      final result = formulaWithPrices.interpret();
      return (result).toDouble();
    } catch (e) {
      throw Exception(
        'Ошибка при вычислении формулы: $e. Обработанная формула: $formulaWithPrices',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double>(
      future: _profitFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Row(
            children: [
              Text('Прибыль: '),
              SizedBox(width: 8),
              SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          );
        }
        if (snapshot.hasError) {
          return Tooltip(
            message: snapshot.error.toString(),
            child: Text(
              'Прибыль: Ошибка',
              style: TextStyle(color: Colors.orange.shade800),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Text('Прибыль: Не удалось рассчитать');
        }

        final profit = snapshot.data!;
        return Text(
          'Прибыль: ${profit.toStringAsFixed(2)} з',
          style: TextStyle(
            color: profit > 0 ? Colors.green.shade600 : Colors.red.shade600,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        );
      },
    );
  }
}
