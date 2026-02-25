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
  bool _isRenaming = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Timer? _timer;

  final Stream<QuerySnapshot> _favoritesStream =
      FirebaseFirestore.instance.collection('favorites').orderBy('name').snapshots();

  @override
  void initState() {
    super.initState();
    // Start the timer to update prices every hour
    _timer = Timer.periodic(const Duration(hours: 1), (timer) {
      _updateFavoritePrices();
    });
    // Also update prices once immediately when the screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateFavoritePrices();
    });
  }

  @override
  void dispose() {
    // Cancel the timer when the screen is disposed
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _updateFavoritePrices() async {
    if (_isPriceUpdating) return;
    setState(() => _isPriceUpdating = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Обновление цен началось...')),
      );
    }

    try {
      final favoritesSnapshot = await _firestore.collection('favorites').get();
      final Map<String, int> itemsToUpdate = {
        for (var doc in favoritesSnapshot.docs)
          doc.id: ((doc.data() as Map<String, dynamic>)['analysisVolume'] ?? 1000) as int
      };

      if (itemsToUpdate.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Нет избранных предметов для обновления.'),
                backgroundColor: Colors.orange),
          );
        }
        setState(() => _isPriceUpdating = false);
        return;
      }

      await BlizzardApiService().fetchReagentPrices(itemsToUpdate);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Цены успешно обновлены!'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Ошибка при обновлении цен: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPriceUpdating = false);
      }
    }
  }

  Future<void> _renameDuplicateFavorites() async {
    if (_isRenaming) return;
    setState(() => _isRenaming = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Проверка и переименование дубликатов...')),
      );
    }

    try {
      final favoritesSnapshot = await _firestore.collection('favorites').get();
      final favorites =
          favoritesSnapshot.docs.map((doc) => AuctionItem.fromFirestore(doc)).toList();

      final Map<String, List<AuctionItem>> itemsByName = {};
      for (var item in favorites) {
        final baseName = item.name.split(' ').take(item.name.split(' ').length - 1).join(' ');
        final nameToGroup = item.name.contains(RegExp(r' \d+$')) ? baseName : item.name;
        
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
              final docRef = _firestore.collection('favorites').doc(item.id.toString());
              batch.update(docRef, {'name': newName});
              renameCount++;
            }
          }
        }
      }

      if (renameCount > 0) {
        await batch.commit();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Переименовано $renameCount дубликатов.'),
                backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Дубликаты не найдены.'),
                backgroundColor: Colors.orange),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Ошибка при переименовании: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRenaming = false);
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
                    return const Center(child: Text('Нет избранных предметов.'));
                  }
                  return ListView.builder(
                    itemCount: favoriteDocs.length,
                    itemBuilder: (context, index) {
                      final item = AuctionItem.fromFirestore(favoriteDocs[index]);
                      return _buildItemRow(context, item, true, index);
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
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3))
              : const Icon(Icons.refresh, size: 20),
          label: const Text('Обновить все цены'),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          style: buttonStyle,
          onPressed: _isRenaming ? null : _renameDuplicateFavorites,
          child: _isRenaming
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3))
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
          Expanded(flex: 2, child: Text('Название', style: theme.textTheme.titleMedium)),
          SizedBox(width: 100, child: Text('Объем', style: theme.textTheme.titleMedium, textAlign: TextAlign.center)),
          Expanded(flex: 3, child: Center(child: Text('График цен', style: theme.textTheme.titleMedium))),
          SizedBox(width: 120, child: Text('Средняя цена', style: theme.textTheme.titleMedium, textAlign: TextAlign.right)),
          const SizedBox(width: 40), // Star icon
        ],
      ),
    );
  }

   Widget _buildItemRow(
      BuildContext context, AuctionItem item, bool isFavorited, int index) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Row(
          key: ValueKey(item.id),
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD4BF7A), width: 1.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: item.iconUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(3.0),
                      child: Image.network(item.iconUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) =>
                              const Icon(Icons.error, size: 20)),
                    )
                  : const Icon(Icons.inventory_2, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: Text(item.name, style: Theme.of(context).textTheme.bodyLarge)),
            SizedBox(
              width: 100,
              child: InkWell(
                onTap: () => _showEditVolumeDialog(context, item),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(item.analysisVolume.toString(), style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(width: 8),
                    const Icon(Icons.edit, size: 16, color: Colors.grey),
                  ],
                ),
              ),
            ),
            Expanded(flex: 3, child: _buildPriceHistoryChart(item, index)),
            SizedBox(
                width: 120,
                child: Text(item.weightedAveragePrice?.toStringAsFixed(2) ?? '-',
                    textAlign: TextAlign.right)),

            GestureDetector(
              onTap: () => _toggleFavorite(context, item, isFavorited),
              child: Container(
                width: 40,
                height: 40,
                color: Colors.transparent,
                alignment: Alignment.center,
                child: Tooltip(
                  message: isFavorited
                      ? 'Удалить из избранного'
                      : 'Добавить в избранное',
                  child: Icon(
                    isFavorited ? Icons.star : Icons.star_border,
                    color: isFavorited
                        ? const Color(0xFFFFC700)
                        : const Color(0xFFD4BF7A),
                    size: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditVolumeDialog(BuildContext context, AuctionItem item) {
    final controller = TextEditingController(text: item.analysisVolume.toString());
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Введите корректное число.'),
                        backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
  }


  Widget _buildPriceHistoryChart(AuctionItem item, int index) {
    final history = item.averagePriceHistory;
    if (history == null || history.isEmpty) {
      return Center(child: Text('-', style: TextStyle(color: Colors.grey[600])));
    }

    if (history.isEmpty) {
      return Center(child: Text('Нет данных', style: TextStyle(color: Colors.grey[600])));
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
       return Center(child: Text('Недостаточно данных', style: TextStyle(color: Colors.grey[600])));
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
                  if (spotIndex < 0 || spotIndex >= sortedKeys.length) return null;
                  final date = DateFormat('dd MMM').format(DateTime.parse(sortedKeys[spotIndex]));
                  final price = barSpot.y.toStringAsFixed(2);
                  return LineTooltipItem(
                    '$date\n$price g',
                    const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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

  void _toggleFavorite(BuildContext context, AuctionItem item, bool isFavorited) {
    final collection = FirebaseFirestore.instance.collection('favorites');
    final docId = item.id.toString();

    if (isFavorited) {
      showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Подтверждение'),
            content: Text('Вы уверены, что хотите удалить "${item.name}" из избранного?'),
            actions: <Widget>[
              TextButton(child: const Text('Отмена'), onPressed: () => Navigator.of(dialogContext).pop()),
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
    } else {
      collection.doc(docId).set(item.toFirestore());
    }
  }
}
