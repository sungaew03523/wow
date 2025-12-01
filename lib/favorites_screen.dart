import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'blizzard_api_service.dart';
import 'models/auction_item.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  int _countForAverage = 10;
  bool _isPriceUpdating = false;
  bool _isRenaming = false;
  final TextEditingController _countController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Stream<QuerySnapshot> _favoritesStream =
      FirebaseFirestore.instance.collection('favorites').snapshots();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _countController.addListener(_saveSettings);
  }

  @override
  void dispose() {
    _countController.removeListener(_saveSettings);
    _countController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final doc =
          await _firestore.collection('settings').doc('user_settings').get();
      if (doc.exists && doc.data()!.containsKey('countForAverage')) {
        setState(() {
          _countForAverage = doc.data()!['countForAverage'];
          _countController.text = _countForAverage.toString();
        });
      } else {
        _countController.text = _countForAverage.toString();
      }
    } catch (e) {
      print("Ошибка загрузки настроек: $e");
      _countController.text = _countForAverage.toString();
    }
  }

  Future<void> _saveSettings() async {
    final newCount = int.tryParse(_countController.text);
    if (newCount != null && newCount > 0 && newCount != _countForAverage) {
      setState(() {
        _countForAverage = newCount;
      });
      try {
        await _firestore.collection('settings').doc('user_settings').set(
            {'countForAverage': newCount},
            SetOptions(merge: true));
      } catch (e) {
        print("Ошибка сохранения настроек: $e");
      }
    }
  }

  Future<void> _updateFavoritePrices() async {
    setState(() => _isPriceUpdating = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Обновление цен началось...')),
      );
    }

    try {
      final favoriteIds = (await _firestore.collection('favorites').get())
          .docs
          .map((doc) => doc.id)
          .toList();
      if (favoriteIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Нет избранных предметов для обновления.'),
                backgroundColor: Colors.orange),
          );
        }
        return;
      }

      await BlizzardApiService().fetchReagentPrices(_countForAverage, favoriteIds);

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
        if (itemsByName.containsKey(item.name)) {
          itemsByName[item.name]!.add(item);
        } else {
          itemsByName[item.name] = [item];
        }
      }

      final WriteBatch batch = _firestore.batch();
      int renameCount = 0;

      for (var entry in itemsByName.entries) {
        if (entry.value.length > 1) {
          final items = entry.value;
          items.sort((a, b) => a.id.compareTo(b.id));

          for (int i = 0; i < items.length; i++) {
            final item = items[i];
            final newName = '${item.name} ${i + 1}';
            final docRef =
                _firestore.collection('favorites').doc(item.id.toString());
            batch.update(docRef, {'name': newName});
            renameCount++;
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildControls(context),
            const SizedBox(height: 20),
            _buildFavoritesHeader(Theme.of(context)),
            const Divider(color: Colors.grey),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _favoritesStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(child: Text('Что-то пошло не так'));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final favoriteDocs = snapshot.data?.docs ?? [];
                  if (favoriteDocs.isEmpty) {
                    return const Center(
                        child: Text(
                      'Нет избранных предметов.',
                      style: TextStyle(color: Colors.grey),
                    ));
                  }

                  return ListView.builder(
                    itemCount: favoriteDocs.length,
                    itemBuilder: (context, index) {
                      final item =
                          AuctionItem.fromFirestore(favoriteDocs[index]);
                      return _buildItemRow(context, item, true);
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
      backgroundColor: const Color(0xFF1E3A8A),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    );

    return Row(
      children: [
        SizedBox(
          width: 200,
          child: TextField(
            controller: _countController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Кол-во для средней цены',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
        const Spacer(),
        if (_isPriceUpdating)
          const CircularProgressIndicator()
        else
          ElevatedButton.icon(
            onPressed: _updateFavoritePrices,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Обновить цены'),
            style: buttonStyle,
          ),
        const SizedBox(width: 10),
        if (_isRenaming)
          const CircularProgressIndicator()
        else
          ElevatedButton(
            onPressed: _renameDuplicateFavorites,
            style: buttonStyle,
            child: const Text('Переименовать дубликаты'),
          ),
      ],
    );
  }

  Widget _buildFavoritesHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        children: [
          const SizedBox(width: 52), // Icon + padding
          Expanded(flex: 2, child: Text('Название', style: theme.textTheme.titleMedium)),
          Expanded(flex: 3, child: Text('График', style: theme.textTheme.titleMedium)),
          SizedBox(
              width: 100,
              child: Text('Мин. цена',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.right)),
          SizedBox(
              width: 120,
              child: Text('Сред. цена',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.right)),
          const SizedBox(width: 40), // For the star icon
        ],
      ),
    );
  }

  Widget _buildItemRow(BuildContext context, AuctionItem item, bool isFavorited) {
    return Padding(
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
          Expanded(flex: 3, child: _buildPriceHistoryChart(item)),
          SizedBox(
              width: 100,
              child: Text(item.minimalCost?.toStringAsFixed(2) ?? '-',
                  textAlign: TextAlign.right)),
          SizedBox(
              width: 120,
              child: Text(item.averageCost?.toStringAsFixed(2) ?? '-',
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
    );
  }


  Widget _buildPriceHistoryChart(AuctionItem item) {
    final history = item.averagePriceHistory;
    if (history == null || history.isEmpty) {
      return const SizedBox.shrink();
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

    if (spots.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 40, // Компактная высота
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
           lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                return touchedBarSpots.map((barSpot) {
                  final spotIndex = barSpot.spotIndex;
                  if (spotIndex < 0 || spotIndex >= sortedKeys.length) {
                    return null;
                  }
                  
                  final date = DateFormat('yyyy-MM-dd').format(DateTime.parse(sortedKeys[spotIndex]));
                  final price = barSpot.y.toStringAsFixed(2);

                  return LineTooltipItem(
                    '$date\n$price',
                    const TextStyle(color: Colors.white, fontSize: 12),
                  );
                }).where((item) => item != null).toList().cast<LineTooltipItem>();
              },
            ),
          ),
          minX: 0,
          maxX: (spots.length - 1).toDouble(),
          minY: minY * 0.95,
          maxY: maxY * 1.05,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.greenAccent, // Яркий цвет для видимости
              barWidth: 2,
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
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Подтверждение'),
            content:
                Text('Вы уверены, что хотите удалить "${item.name}" из избранного?'),
            actions: <Widget>[
              TextButton(
                child: const Text('Отмена'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  collection.doc(docId).delete();
                  Navigator.of(context).pop();
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
