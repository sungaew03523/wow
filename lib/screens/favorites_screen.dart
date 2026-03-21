import 'dart:async';
import 'dart:math';
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
  bool _isRenaming = false;
  bool _isClearingHistory = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final BlizzardApiService _apiService = BlizzardApiService();
  Timer? _timer;
  String? _selectedFilterProfession;
  bool _isSelectionMode = false;
  final Set<int> _selectedIds = {};

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

  final Stream<QuerySnapshot> _favoritesStream = FirebaseFirestore.instance
      .collection('favorites')
      .orderBy('name')
      .snapshots();

  @override
  void initState() {
    super.initState();
    _scheduleNextUpdate();
  }

  void _scheduleNextUpdate() {
    if (!mounted) return;

    final now = DateTime.now();
    var nextUpdate = DateTime(now.year, now.month, now.day, now.hour, 30);

    if (now.isAfter(nextUpdate) || now.isAtSameMomentAs(nextUpdate)) {
      nextUpdate = nextUpdate.add(const Duration(hours: 1));
    }

    final waitDuration = nextUpdate.difference(now);

    _timer = Timer(waitDuration, () {
      if (mounted) {
        _updateFavoritePrices();
        _scheduleNextUpdate();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
          doc.id: ((doc.data())['analysisVolume'] ?? 1000)
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
      const SnackBar(content: Text('Проверка и переименование дубликатов...')),
    );

    try {
      final favoritesSnapshot = await _firestore.collection('favorites').get();
      final favorites = favoritesSnapshot.docs
          .map((doc) => AuctionItem.fromFirestore(doc))
          .toList();

      final Map<String, List<AuctionItem>> itemsByName = {};
      for (var item in favorites) {
        final baseName = item.name
            .split(' ')
            .take(item.name.split(' ').length - 1)
            .join(' ');
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

  Future<void> _clearAllHistory() async {
    if (_isClearingHistory) return;

    if (!mounted) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Подтверждение'),
          content: const Text(
              'Вы уверены, что хотите удалить ВСЮ историю цен и количества для ВСЕХ избранных предметов? Это действие необратимо.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Удалить всю историю'),
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
      const SnackBar(content: Text('Очистка всей истории...')),
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
        batch.update(doc.reference, {
          'averagePriceHistory': {},
          'totalQuantityHistory': {},
        });
      }

      await batch.commit();

      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        const SnackBar(
            content: Text('Вся история успешно очищена!'),
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

  void _showBulkProfessionsDialog() {
    List<String> selected = [];
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Массовое назначение профессий'),
          content: SizedBox(
            width: 300,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _professions.map((p) => CheckboxListTile(
                  title: Text(p),
                  value: selected.contains(p),
                  onChanged: (val) => setDialogState(() {
                    if (val == true) selected.add(p); else selected.remove(p);
                  }),
                )).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () async {
                final batch = _firestore.batch();
                for (var id in _selectedIds) {
                  batch.update(_firestore.collection('favorites').doc(id.toString()), {'professions': selected});
                }
                await batch.commit();
                if (mounted) {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedIds.clear();
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
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
                stream: _firestore.collection('investments').snapshots(),
                builder: (context, investSnapshot) {
                  final allInvestments = investSnapshot.data?.docs ?? [];

                  // Группируем инвестиции по itemId для быстрого доступа
                  final Map<String, List<DocumentSnapshot>> investmentsByItem =
                      {};
                  for (var doc in allInvestments) {
                    final data = doc.data() as Map<String, dynamic>;
                    final itemId = data['itemId'] as String?;
                    if (itemId != null) {
                      investmentsByItem.putIfAbsent(itemId, () => []).add(doc);
                    }
                  }

                  return StreamBuilder<QuerySnapshot>(
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

                      var favoriteItems = favoriteDocs.map((doc) => AuctionItem.fromFirestore(doc)).toList();
                      
                      if (_selectedFilterProfession != null) {
                        favoriteItems = favoriteItems.where((item) => 
                          item.professions.contains(_selectedFilterProfession)).toList();
                      }

                      if (favoriteItems.isEmpty) {
                        return const Center(child: Text('Нет предметов для выбранной профессии.'));
                      }

                      return ListView.builder(
                        itemCount: favoriteItems.length,
                        itemBuilder: (context, index) {
                          final item = favoriteItems[index];
                          final itemInvestments =
                              investmentsByItem[item.id.toString()] ?? [];
                          return FavoriteItemRow(
                            item: item,
                            itemInvestments: itemInvestments,
                            allProfessions: _professions,
                            key: ValueKey(item.id),
                            isSelected: _selectedIds.contains(item.id),
                            isSelectionMode: _isSelectionMode,
                            onToggleSelection: (id) {
                              setState(() {
                                if (_selectedIds.contains(id)) {
                                  _selectedIds.remove(id);
                                } else {
                                  _selectedIds.add(id);
                                }
                              });
                            },
                          );
                        },
                      );
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
        DropdownButton<String?>(
          value: _selectedFilterProfession,
          hint: const Text('Фильтр по профессии'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Все профессии')),
            ..._professions.map((p) => DropdownMenuItem(value: p, child: Text(p))),
          ],
          onChanged: (val) {
            setState(() => _selectedFilterProfession = val);
          },
        ),
        const SizedBox(width: 8),
        if (_isSelectionMode && _selectedIds.isNotEmpty)
          ElevatedButton.icon(
            style: buttonStyle.copyWith(backgroundColor: WidgetStateProperty.all(Colors.blueGrey)),
            onPressed: _showBulkProfessionsDialog,
            icon: const Icon(Icons.assignment, size: 20),
            label: Text('Назначить (${_selectedIds.length})'),
          ),
        IconButton(
          icon: Icon(_isSelectionMode ? Icons.check_box : Icons.check_box_outline_blank),
          tooltip: _isSelectionMode ? 'Выйти из режима выбора' : 'Режим выбора',
          onPressed: () {
            setState(() {
              _isSelectionMode = !_isSelectionMode;
              if (!_isSelectionMode) _selectedIds.clear();
            });
          },
        ),
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
          onPressed: _isClearingHistory ? null : _clearAllHistory,
          icon: _isClearingHistory
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 3))
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
          if (_isSelectionMode)
            const SizedBox(
              width: 52,
              child: Center(child: Icon(Icons.check_box_outline_blank, size: 20, color: Colors.grey)),
            )
          else
            const SizedBox(width: 52), // Icon + padding
          Expanded(
              flex: 2,
              child: Text('Название', style: theme.textTheme.titleMedium)),
          SizedBox(
              width: 120,
              child: Text('Профессии',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center)),
          SizedBox(
              width: 100,
              child: Text('Объем',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center)),
          Expanded(
              flex: 3,
              child: Center(
                  child: Text('График', style: theme.textTheme.titleMedium))),
          SizedBox(
            width: 150,
            child: Text('Инвестиции',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center),
          ),
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
  final List<DocumentSnapshot> itemInvestments;
  final List<String> allProfessions;
  final bool isSelected;
  final bool isSelectionMode;
  final Function(int) onToggleSelection;

  const FavoriteItemRow({
    required this.item,
    required this.itemInvestments,
    required this.allProfessions,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onToggleSelection,
    super.key,
  });

  @override
  State<FavoriteItemRow> createState() => _FavoriteItemRowState();
}

class _FavoriteItemRowState extends State<FavoriteItemRow> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2.0),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: InkWell(
        onTap: widget.isSelectionMode ? () => widget.onToggleSelection(widget.item.id) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: Row(
            children: [
              if (widget.isSelectionMode)
                Checkbox(
                  value: widget.isSelected,
                  onChanged: (val) => widget.onToggleSelection(widget.item.id),
                ),
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
                child: Text(widget.item.name,
                    style: Theme.of(context).textTheme.bodyLarge)),
            SizedBox(
              width: 120, 
              child: _buildProfessionsCell(context),
            ),
            SizedBox(
              width: 100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    (() {
                      final history = widget.item.totalQuantityHistory;
                      final totalQty = (history != null && history.isNotEmpty)
                          ? history.values.last
                          : 0;
                      if (totalQty == 0) return '-';
                      int vol = (totalQty * 0.10).ceil();
                      if (vol < 1) vol = 1;
                      if (vol > 3000) vol = 3000;
                      return vol.toString();
                    })(),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            Expanded(
                flex: 3, child: _buildPriceHistoryChart(context, widget.item)),
            SizedBox(
              width: 150,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_shopping_cart),
                    tooltip: 'Добавить/Изменить покупку',
                    onPressed: () =>
                        _showAddInvestmentDialog(context, widget.item),
                  ),
                  _buildProfitDisplay(widget.item, widget.itemInvestments),
                ],
              ),
            ),
            SizedBox(
              width: 90,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Tooltip(
                    message: 'Очистить историю предмета',
                    child: IconButton(
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.history_toggle_off_outlined),
                      onPressed: () =>
                          _clearSingleItemHistory(context, widget.item),
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
    ),
  );
}

  Future<void> _showAddInvestmentDialog(
      BuildContext context, AuctionItem item) async {
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

    final quantityController = TextEditingController(
        text: totalQuantity > 0 ? totalQuantity.toString() : '');
    final priceController = TextEditingController(
        text: averagePrice > 0 ? averagePrice.toStringAsFixed(2) : '');
    final formKey = GlobalKey<FormState>();

    if (!context.mounted) return;

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
                  decoration:
                      const InputDecoration(labelText: 'Общее количество'),
                  validator: (value) {
                    if (value == null ||
                        value.isEmpty ||
                        int.tryParse(value) == null ||
                        int.parse(value) < 0) {
                      return 'Введите корректное число';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: priceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Средняя цена закупки (за шт.)'),
                  validator: (value) {
                    if (value == null ||
                        value.isEmpty ||
                        double.tryParse(value) == null ||
                        double.parse(value) < 0) {
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

                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(quantity > 0
                              ? 'Инвестиция успешно сохранена!'
                              : 'Инвестиция удалена.'),
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

  Widget _buildProfitDisplay(
      AuctionItem item, List<DocumentSnapshot> snapshots) {
    if (snapshots.isEmpty) {
      return Text('0 g', style: Theme.of(context).textTheme.bodyLarge);
    }

    int totalQuantity = 0;
    double totalCost = 0;

    for (var doc in snapshots) {
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

    final currentValue =
        (currentWeightedPrice * totalQuantity) * 0.95; // -5% commission
    final profit = currentValue - totalCost;

    final profitColor = profit >= 0 ? Colors.greenAccent : Colors.redAccent;
    final profitSign = profit > 0 ? '+' : '';

    return Tooltip(
        message:
            'Всего куплено: $totalQuantity шт.\nСредняя цена покупки: ${(totalCost / totalQuantity).toStringAsFixed(2)} g',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${totalCost.toStringAsFixed(0)} g',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.amber, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              '$profitSign${profit.toStringAsFixed(0)} g',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: profitColor, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ));
  }

  Widget _buildProfessionsCell(BuildContext context) {
    final professions = widget.item.professions;
    
    return InkWell(
      onTap: () => _showProfessionsDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: professions.isEmpty
            ? const Center(
                child: Icon(Icons.add_circle_outline, 
                    size: 18, color: Colors.grey),
              )
            : Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: professions.map((p) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withAlpha(50),
                    border: Border.all(color: Colors.blueAccent, width: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    p.substring(0, 1).toUpperCase(), // Показываем первую букву
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                )).toList(),
              ),
      ),
    );
  }

  void _showProfessionsDialog(BuildContext context) {
    List<String> selected = List<String>.from(widget.item.professions);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Профессии для "${widget.item.name}"'),
              content: SizedBox(
                width: 300,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.allProfessions.map((p) {
                      final isSelected = selected.contains(p);
                      return CheckboxListTile(
                        title: Text(p),
                        value: isSelected,
                        onChanged: (val) {
                          setDialogState(() {
                            if (val == true) {
                              selected.add(p);
                            } else {
                              selected.remove(p);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await FirebaseFirestore.instance
                        .collection('favorites')
                        .doc(widget.item.id.toString())
                        .update({'professions': selected});
                    if (mounted) Navigator.pop(context);
                  },
                  child: const Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPriceHistoryChart(BuildContext context, AuctionItem item) {
    final priceHistory = item.averagePriceHistory;
    final quantityHistory = item.totalQuantityHistory;

    if (priceHistory == null || priceHistory.length < 2) {
      return Center(
          child: Text('Недостаточно данных',
              style: TextStyle(color: Colors.grey[600])));
    }

    final sortedKeys = priceHistory.keys.toList()..sort();

    List<FlSpot> priceSpots = [];
    List<FlSpot> quantitySpotsRaw = [];
    double minPrice = double.maxFinite, maxPrice = double.minPositive;
    double minQuantity = double.maxFinite, maxQuantity = double.minPositive;

    for (var i = 0; i < sortedKeys.length; i++) {
      final key = sortedKeys[i];
      final priceValue = priceHistory[key];
      final quantityValue = quantityHistory?[key];

      if (priceValue != null) {
        final doublePrice = priceValue.toDouble();
        priceSpots.add(FlSpot(i.toDouble(), doublePrice));
        minPrice = min(minPrice, doublePrice);
        maxPrice = max(maxPrice, doublePrice);
      }

      if (quantityValue != null) {
        final doubleQuantity = quantityValue.toDouble();
        quantitySpotsRaw.add(FlSpot(i.toDouble(), doubleQuantity));
        minQuantity = min(minQuantity, doubleQuantity);
        maxQuantity = max(maxQuantity, doubleQuantity);
      }
    }

    final bool showQuantityLine = quantitySpotsRaw.length > 1;
    final bool isPriceFlat = (maxPrice - minPrice).abs() < 0.01;
    final bool isQuantityFlat = (maxQuantity - minQuantity).abs() < 0.01;

    final priceRange = !isPriceFlat ? (maxPrice - minPrice) : 1.0;
    double paddedMinPrice =
        isPriceFlat ? minPrice - priceRange * 0.5 : minPrice - priceRange * 0.2;
    if (paddedMinPrice < 0) paddedMinPrice = 0;
    final paddedMaxPrice =
        isPriceFlat ? maxPrice + priceRange * 0.5 : maxPrice + priceRange * 0.2;
    final paddedPriceRange = paddedMaxPrice - paddedMinPrice;

    final quantityRange = !isQuantityFlat ? (maxQuantity - minQuantity) : 1.0;

    List<FlSpot> quantitySpotsNormalized = [];
    if (showQuantityLine) {
      if (!isQuantityFlat) {
        quantitySpotsNormalized = quantitySpotsRaw.map((spot) {
          final normalizedY = paddedMinPrice +
              (spot.y - minQuantity) * paddedPriceRange / quantityRange;
          return FlSpot(spot.x, normalizedY);
        }).toList();
      } else {
        final avgPrice = (paddedMinPrice + paddedMaxPrice) / 2;
        quantitySpotsNormalized =
            quantitySpotsRaw.map((spot) => FlSpot(spot.x, avgPrice)).toList();
      }
    }

    Widget getSideTitleWidget(double value, TitleMeta meta, bool isLeft) {
      if (value != meta.min && value != meta.max) {
        return const SizedBox.shrink();
      }

      final style = TextStyle(
        fontSize: 10,
        color: (isLeft ? Colors.greenAccent : Colors.redAccent).withAlpha(178),
      );

      String titleText;
      if (isLeft) {
        titleText = value.toStringAsFixed(0);
      } else {
        final denormalized = minQuantity +
            (value - paddedMinPrice) * quantityRange / paddedPriceRange;
        titleText = NumberFormat.compact().format(max(0, denormalized));
      }

      return Text(titleText,
          style: style, textAlign: isLeft ? TextAlign.left : TextAlign.right);
    }

    return SizedBox(
      height: 90,
      child: Stack(
        children: [
          LineChart(
            LineChartData(
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              minY: paddedMinPrice,
              maxY: paddedMaxPrice,
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (touchedSpot) => Colors.black.withAlpha(204),
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (touchedSpots) {
                    if (touchedSpots.isEmpty) return [];
                    return touchedSpots.map((spot) {
                      if (spot != touchedSpots.first) return null;

                      final spotIndex = spot.spotIndex;
                      if (spotIndex >= sortedKeys.length) return null;

                      final keyString = sortedKeys[spotIndex];
                      DateTime? parsedDate = DateTime.tryParse(keyString);

                      if (parsedDate == null &&
                          keyString.length == 13 &&
                          keyString.contains(' ')) {
                        final fixedString =
                            '${keyString.replaceFirst(' ', 'T')}:00:00';
                        parsedDate = DateTime.tryParse(fixedString);
                      }

                      final finalDate = parsedDate ?? DateTime.now();
                      final date = DateFormat('dd.MM HH:mm').format(finalDate);

                      final children = <TextSpan>[];
                      if (showQuantityLine &&
                          spotIndex < quantitySpotsRaw.length) {
                        children.add(TextSpan(
                          text:
                              '${NumberFormat.compact().format(quantitySpotsRaw[spotIndex].y)}\n',
                          style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ));
                      }
                      if (spotIndex < priceSpots.length) {
                        children.add(TextSpan(
                          text: priceSpots[spotIndex].y.toStringAsFixed(2),
                          style: const TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ));
                      }

                      return LineTooltipItem(
                        '$date\n',
                        const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                        children: children,
                      );
                    }).toList();
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 60,
                    interval: paddedPriceRange / 2 * 1.05,
                    getTitlesWidget: (v, m) => getSideTitleWidget(v, m, true),
                  ),
                ),
                rightTitles: AxisTitles(
                  sideTitles: showQuantityLine
                      ? SideTitles(
                          showTitles: true,
                          reservedSize: 45,
                          interval: paddedPriceRange / 2 * 1.05,
                          getTitlesWidget: (v, m) =>
                              getSideTitleWidget(v, m, false),
                        )
                      : const SideTitles(showTitles: false),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: priceSpots,
                  isCurved: true,
                  color: Colors.greenAccent,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                      show: true, color: Colors.greenAccent.withAlpha(40)),
                ),
                if (showQuantityLine)
                  LineChartBarData(
                    spots: quantitySpotsNormalized,
                    isCurved: true,
                    color: Colors.redAccent,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 60,
              child: Text(
                item.weightedAveragePrice != null
                    ? item.weightedAveragePrice!.toStringAsFixed(2)
                    : '-',
                style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.left,
              ),
            ),
          ),
          if (showQuantityLine)
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 45,
                child: Text(
                  NumberFormat.compact()
                      .format(item.totalQuantityHistory?.values.last ?? 0),
                  style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.right,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _clearSingleItemHistory(
      BuildContext context, AuctionItem item) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Подтверждение'),
          content: Text(
              'Вы уверены, что хотите удалить историю цен и количества для "${item.name}"?'),
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
      await _firestore.collection('favorites').doc(item.id.toString()).update({
        'averagePriceHistory': {},
        'totalQuantityHistory': {},
      });

      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
            content: Text('История для "${item.name}" очищена.'),
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
