import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../blizzard_api_service.dart';
import '../models/auction_item.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  bool _isPriceUpdating = false;
  bool _isCalculatingVolumes = false;
  bool _isRenaming = false;
  bool _isClearingHistory = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final BlizzardApiService _apiService = BlizzardApiService();
  Timer? _timer;

  final Stream<QuerySnapshot> _favoritesStream =
      FirebaseFirestore.instance.collection('favorites').orderBy('name').snapshots();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(hours: 1), (timer) {
      _updateFavoritePrices();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateFavoritePrices();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _calculateAndSetVolumes() async {
    if (_isCalculatingVolumes) return;
    setState(() => _isCalculatingVolumes = true);

    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('Начинаем расчет объемов...')),
    );

    try {
      final favoritesSnapshot = await _firestore.collection('favorites').get();
      if (favoritesSnapshot.docs.isEmpty) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Нет избранных предметов для расчета.'), backgroundColor: Colors.orange),
        );
        setState(() => _isCalculatingVolumes = false);
        return;
      }

      final itemIds = favoritesSnapshot.docs.map((doc) => doc.id).toList();
      final itemQuantities = await _apiService.getAuctionQuantities(itemIds);

      final WriteBatch batch = _firestore.batch();

      for (var doc in favoritesSnapshot.docs) {
        final totalQuantity = itemQuantities[doc.id] ?? 0;
        int newVolume;

        if (totalQuantity > 10000) {
          newVolume = 1000;
        } else if (totalQuantity > 5000) {
          newVolume = 500;
        } else if (totalQuantity > 1000) {
          newVolume = 100;
        } else if (totalQuantity > 500) {
          newVolume = 50;
        } else if (totalQuantity > 100) {
          newVolume = 10;
        } else {
          newVolume = 5;
        }

        batch.update(doc.reference, {'analysisVolume': newVolume});
      }

      await batch.commit();

       scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Объемы успешно рассчитаны и обновлены!'), backgroundColor: Colors.green),
      );

    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Ошибка при расчете объемов: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isCalculatingVolumes = false);
      }
    }
  }


  Future<void> _updateFavoritePrices() async {
    if (_isPriceUpdating) return;
    setState(() => _isPriceUpdating = true);
    
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('Обновление цен началось...')),
    );

    try {
      final favoritesSnapshot = await _firestore.collection('favorites').get();
      final Map<String, int> itemsToUpdate = {
        for (var doc in favoritesSnapshot.docs)
          doc.id:
              ((doc.data())['analysisVolume'] ?? 1000)
      };

      if (itemsToUpdate.isEmpty) {
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          const SnackBar(
              content: Text('Нет избранных предметов для обновления.'),
              backgroundColor: Colors.orange),
        );
        setState(() => _isPriceUpdating = false);
        return;
      }

      await _apiService.fetchReagentPrices(itemsToUpdate);

      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        const SnackBar(
            content: Text('Цены успешно обновлены!'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
            content: Text('Ошибка при обновлении цен: $e'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isPriceUpdating = false);
      }
    }
  }

  Future<void> _renameDuplicateFavorites() async {
    if (_isRenaming) return;
    setState(() => _isRenaming = true);
    
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    scaffoldMessenger.showSnackBar(
      const SnackBar(
          content: Text('Проверка и переименование дубликатов...')),
    );

    try {
      final favoritesSnapshot = await _firestore.collection('favorites').get();
      final favorites =
          favoritesSnapshot.docs.map((doc) => AuctionItem.fromFirestore(doc)).toList();

      final Map<String, List<AuctionItem>> itemsByName = {};
      for (var item in favorites) {
        final baseName = item.name.split(' ').take(item.name.split(' ').length - 1).join(' ');
        final nameToGroup =
            item.name.contains(RegExp(r' \d+$')) ? baseName : item.name;

        itemsByName.putIfAbsent(nameToGroup, () => []).add(item);
      }

      final WriteBatch batch = _firestore.batch();
      int renameCount = 0;

      for (var entry in itemsByName.entries) {
        if (entry.value.length > 1) {
          final items = entry.value;
          items.sort((a, b) => a.id.compareTo(b.id));

          for (int i = 0; i < items.length; i++) {
            final item = items[i];
            final newName = '${entry.key} ${i + 1}';
            if (item.name != newName) {
              final docRef =
                  _firestore.collection('favorites').doc(item.id.toString());
              batch.update(docRef, {'name': newName});
              renameCount++;
            }
          }
        }
      }

      if (renameCount > 0) {
        await batch.commit();
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          SnackBar(
              content: Text('Переименовано $renameCount дубликатов.'),
              backgroundColor: Colors.green),
        );
      } else {
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          const SnackBar(
              content: Text('Дубликаты не найдены.'),
              backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
            content: Text('Ошибка при переименовании: $e'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isRenaming = false);
      }
    }
  }

  Future<void> _clearPriceHistory() async {
    if (_isClearingHistory) return;

    if (!mounted) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Подтверждение'),
          content: const Text(
              'Вы уверены, что хотите удалить историю цен для ВСЕХ избранных предметов? Это действие необратимо.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _isClearingHistory = true);
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('Очистка истории цен...')),
    );

    try {
      final favoritesSnapshot = await _firestore.collection('favorites').get();
      if (favoritesSnapshot.docs.isEmpty) {
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          const SnackBar(
              content: Text('Нет предметов для очистки.'),
              backgroundColor: Colors.orange),
        );
        return;
      }

      final WriteBatch batch = _firestore.batch();

      for (var doc in favoritesSnapshot.docs) {
        batch.update(doc.reference, {'averagePriceHistory': {}});
      }

      await batch.commit();

      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        const SnackBar(
            content: Text('История цен успешно очищена!'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
            content: Text('Ошибка при очистке истории: $e'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isClearingHistory = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Избранное'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          tooltip: 'На главную',
          onPressed: () => context.go('/'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildControls(context),
            const SizedBox(height: 20),
            _buildFavoritesHeader(Theme.of(context)),
            const Divider(color: Colors.grey, height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _favoritesStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Ошибка: ${snapshot.error}'));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final favoriteDocs = snapshot.data?.docs ?? [];
                  if (favoriteDocs.isEmpty) {
                    return const Center(
                        child: Text('Нет избранных предметов.'));
                  }
                  return ListView.builder(
                    itemCount: favoriteDocs.length,
                    itemBuilder: (context, index) {
                      final item =
                          AuctionItem.fromFirestore(favoriteDocs[index]);
                      return FavoriteItemRow(item: item, key: ValueKey(item.id));
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final buttonStyle = ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      side: const BorderSide(color: Color(0xFFD4BF7A), width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ElevatedButton.icon(
          style: buttonStyle,
          onPressed: _isPriceUpdating ? null : _updateFavoritePrices,
          icon: _isPriceUpdating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 3))
              : const Icon(Icons.refresh, size: 20),
          label: const Text('Обновить все цены'),
        ),
        ElevatedButton.icon(
          style: buttonStyle,
          onPressed: _isCalculatingVolumes ? null : _calculateAndSetVolumes,
          icon: _isCalculatingVolumes
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 3))
              : const Icon(Icons.calculate_outlined, size: 20),
          label: const Text('Рассчитать объемы'),
        ),
        ElevatedButton.icon(
          style: buttonStyle,
          onPressed: _isClearingHistory ? null : _clearPriceHistory,
          icon: _isClearingHistory
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3))
              : const Icon(Icons.delete_sweep, size: 20),
          label: const Text('Очистить историю'),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          style: buttonStyle,
          onPressed: _isRenaming ? null : _renameDuplicateFavorites,
          child: _isRenaming
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 3))
              : const Text('Переименовать дубликаты'),
        ),
      ],
    );
  }

  Widget _buildFavoritesHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        children: [
          const SizedBox(width: 52), // Icon + padding
          Expanded(
              flex: 2, child: Text('Название', style: theme.textTheme.titleMedium)),
          SizedBox(
              width: 100,
              child: Text('Объем',
                  style: theme.textTheme.titleMedium, textAlign: TextAlign.center)),
          Expanded(
              flex: 3,
              child: Center(
                  child: Text('График цен', style: theme.textTheme.titleMedium))),
          SizedBox(
            width: 150,
            child: Text('Инвестиции', 
                style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          ),
          SizedBox(
              width: 90,
              child: Text('Цена',
                  style: theme.textTheme.titleMedium, textAlign: TextAlign.right)),
          SizedBox(
              width: 90,
              child: Text('Действия',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}


class FavoriteItemRow extends StatefulWidget {
  final AuctionItem item;

  const FavoriteItemRow({required this.item, super.key});

  @override
  State<FavoriteItemRow> createState() => _FavoriteItemRowState();
}

class _FavoriteItemRowState extends State<FavoriteItemRow> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD4BF7A), width: 1.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: widget.item.iconUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(3.0),
                      child: Image.network(widget.item.iconUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) =>
                              const Icon(Icons.error, size: 20)),
                    )
                  : const Icon(Icons.inventory_2, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
                flex: 2,
                child: Text(widget.item.name, style: Theme.of(context).textTheme.bodyLarge)),
            SizedBox(
              width: 100,
              child: InkWell(
                onTap: () => _showEditVolumeDialog(context, widget.item),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(widget.item.analysisVolume.toString(),
                        style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(width: 8),
                    const Icon(Icons.edit, size: 16, color: Colors.grey),
                  ],
                ),
              ),
            ),
            Expanded(flex: 3, child: _buildPriceHistoryChart(widget.item)),
            SizedBox(
              width: 150,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_shopping_cart),
                    tooltip: 'Добавить/Изменить покупку',
                    onPressed: () => _showAddInvestmentDialog(context, widget.item),
                  ),
                  _buildProfitDisplay(widget.item),
                ],
              ),
            ),
            SizedBox(
                width: 90,
                child: Text(widget.item.weightedAveragePrice?.toStringAsFixed(2) ?? '-',
                    textAlign: TextAlign.right)),
            SizedBox(
              width: 90,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Tooltip(
                    message: 'Очистить историю цен',
                    child: IconButton(
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.history_toggle_off_outlined),
                      onPressed: () => _clearSingleItemHistory(context, widget.item),
                      color: Colors.grey[400],
                      iconSize: 20,
                      splashRadius: 18,
                    ),
                  ),
                  Tooltip(
                    message: 'Удалить из избранного',
                    child: IconButton(
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.star),
                      onPressed: () =>
                          _toggleFavorite(context, widget.item, true),
                      color: const Color(0xFFFFC700),
                      iconSize: 22,
                      splashRadius: 18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddInvestmentDialog(BuildContext context, AuctionItem item) async {
    final investmentQuery = _firestore
        .collection('investments')
        .where('itemId', isEqualTo: item.id.toString());

    final existingInvestments = await investmentQuery.get();

    int totalQuantity = 0;
    double totalCost = 0;
    if (existingInvestments.docs.isNotEmpty) {
      for (var doc in existingInvestments.docs) {
        final data = doc.data();
        totalQuantity += (data['quantity'] as int?) ?? 0;
        final price = (data['purchasePrice'] as num?)?.toDouble() ?? 0.0;
        final qty = (data['quantity'] as int?) ?? 0;
        totalCost += price * qty;
      }
    }

    final averagePrice = totalQuantity > 0 ? totalCost / totalQuantity : 0.0;

    final quantityController = TextEditingController(text: totalQuantity > 0 ? totalQuantity.toString() : '');
    final priceController = TextEditingController(text: averagePrice > 0 ? averagePrice.toStringAsFixed(2) : '');
    final formKey = GlobalKey<FormState>();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Инвестиция в "${item.name}"'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Общее количество'),
                  validator: (value) {
                    if (value == null || value.isEmpty || int.tryParse(value) == null || int.parse(value) < 0) {
                      return 'Введите корректное число';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Средняя цена закупки (за шт.)'),
                   validator: (value) {
                    if (value == null || value.isEmpty || double.tryParse(value) == null || double.parse(value) < 0) {
                      return 'Введите корректную цену';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final quantity = int.parse(quantityController.text);
                  final price = double.parse(priceController.text);

                  final batch = _firestore.batch();

                  for (var doc in existingInvestments.docs) {
                    batch.delete(doc.reference);
                  }

                  if (quantity > 0) {
                    batch.set(_firestore.collection('investments').doc(), {
                      'itemId': item.id.toString(),
                      'quantity': quantity,
                      'purchasePrice': price,
                      'timestamp': Timestamp.now(),
                    });
                  }

                  await batch.commit();
                  
                  if(mounted) {
                    Navigator.of(context).pop();
                     ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(quantity > 0 ? 'Инвестиция успешно сохранена!' : 'Инвестиция удалена.'),
                          backgroundColor: Colors.green),
                    );
                  }
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProfitDisplay(AuctionItem item) {
    final Stream<QuerySnapshot> investmentStream = _firestore
        .collection('investments')
        .where('itemId', isEqualTo: item.id.toString())
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: investmentStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Text('0 g', style: Theme.of(context).textTheme.bodyLarge);
        }
        if (snapshot.hasError) {
          return const Tooltip(message: "Ошибка", child: Icon(Icons.error_outline, color: Colors.red, size: 18));
        }

        int totalQuantity = 0;
        double totalCost = 0;

        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          totalQuantity += (data['quantity'] as int?) ?? 0;
          final price = (data['purchasePrice'] as num?)?.toDouble() ?? 0.0;
          final qty = (data['quantity'] as int?) ?? 0;
          totalCost += price * qty;
        }
        
        final currentWeightedPrice = item.weightedAveragePrice;
        if (currentWeightedPrice == null || totalQuantity == 0) {
          return Text('0 g', style: Theme.of(context).textTheme.bodyLarge);
        }

        final currentValue = (currentWeightedPrice * totalQuantity) * 0.95; // -5% commission
        final profit = currentValue - totalCost;
        
        final profitColor = profit >= 0 ? Colors.greenAccent : Colors.redAccent;
        final profitSign = profit > 0 ? '+' : '';

        return Tooltip(
          message: 'Всего куплено: $totalQuantity шт.\nСредняя цена покупки: ${(totalCost / totalQuantity).toStringAsFixed(2)} g',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               Text(
                '${totalCost.toStringAsFixed(0)} g',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.amber, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                '$profitSign${profit.toStringAsFixed(0)} g',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: profitColor, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          )
        );
      },
    );
  }

  void _showEditVolumeDialog(BuildContext context, AuctionItem item) {
    final controller =
        TextEditingController(text: item.analysisVolume.toString());
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Изменить объем для "${item.name}"'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Объем для анализа'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                final newVolume = int.tryParse(controller.text);
                if (newVolume != null && newVolume > 0) {
                  _firestore
                      .collection('favorites')
                      .doc(item.id.toString())
                      .update({'analysisVolume': newVolume});
                  Navigator.of(context).pop();
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Введите корректное число.'),
                          backgroundColor: Colors.red),
                    );
                  } 
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPriceHistoryChart(AuctionItem item) {
    final history = item.averagePriceHistory;
    if (history == null || history.isEmpty) {
      return Center(child: Text('-', style: TextStyle(color: Colors.grey[600])));
    }

    if (history.isEmpty) {
      return Center(
          child: Text('Нет данных', style: TextStyle(color: Colors.grey[600])));
    }

    List<FlSpot> spots = [];
    final sortedKeys = history.keys.toList()..sort();

    double minY = double.maxFinite;
    double maxY = double.minPositive;

    for (var i = 0; i < sortedKeys.length; i++) {
      final key = sortedKeys[i];
      final value = history[key];
      if (value != null) {
        final doubleValue = value.toDouble();
        spots.add(FlSpot(i.toDouble(), doubleValue));
        if (doubleValue < minY) minY = doubleValue;
        if (doubleValue > maxY) maxY = doubleValue;
      }
    }

    if (spots.length < 2) {
      return Center(
          child: Text('Недостаточно данных',
              style: TextStyle(color: Colors.grey[600])));
    }

    return SizedBox(
      height: 40,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (touchedSpot) => const Color(0xFF343a40),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (touchedBarSpots) {
                return touchedBarSpots.map((barSpot) {
                  final spotIndex = barSpot.spotIndex;
                  if (spotIndex < 0 || spotIndex >= sortedKeys.length) {
                    return null;
                  }
                  final date = DateFormat('dd MMM')
                      .format(DateTime.parse(sortedKeys[spotIndex]));
                  final price = barSpot.y.toStringAsFixed(2);
                  return LineTooltipItem(
                    '$date\n$price g',
                    const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  );
                }).whereType<LineTooltipItem>().toList();
              },
            ),
          ),
          minY: minY - (maxY - minY) * 0.1,
          maxY: maxY + (maxY - minY) * 0.1,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.greenAccent,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.greenAccent.withAlpha(50),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearSingleItemHistory(BuildContext context, AuctionItem item) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Подтверждение'),
          content: Text('Вы уверены, что хотите удалить историю цен для "${item.name}"?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _firestore
          .collection('favorites')
          .doc(item.id.toString())
          .update({'averagePriceHistory': {}});

      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
            content: Text('История цен для "${item.name}" очищена.'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
            content: Text('Ошибка при очистке истории для "${item.name}": $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  void _toggleFavorite(
      BuildContext context, AuctionItem item, bool isFavorited) {
    final collection = FirebaseFirestore.instance.collection('favorites');
    final docId = item.id.toString();

    if (isFavorited) {
      showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Подтверждение'),
            content: Text(
                'Вы уверены, что хотите удалить "${item.name}" из избранного?'),
            actions: <Widget>[
              TextButton(
                  child: const Text('Отмена'),
                  onPressed: () => Navigator.of(dialogContext).pop()),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  collection.doc(docId).delete();
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Удалить'),
              ),
            ],
          );
        },
      );
    }
  }
}
