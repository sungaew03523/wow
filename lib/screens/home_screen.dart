import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../blizzard_api_service.dart';
import '../models/auction_item.dart';
import '../app_router.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<AuctionItem> _items = [];
  bool _isLoading = false;
  String _searchQuery = '';
  bool _isTokenPriceLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchAndStoreTokenPrice();
  }

  Future<void> _fetchAndStoreTokenPrice() async {
    if (!mounted) return;
    setState(() => _isTokenPriceLoading = true);

    try {
      final price = await BlizzardApiService().fetchWowTokenPrice();
      final docRef = FirebaseFirestore.instance
          .collection('settings')
          .doc('wow_token_price');

      final now = DateTime.now().toUtc();
      final timestampKey = DateFormat("yyyy-MM-dd HH").format(now);

      await docRef.set({
        'prices': {timestampKey: price}
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Цена жетона успешно обновлена!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при обновлении цены жетона: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTokenPriceLoading = false);
      }
    }
  }

  Future<void> _searchItems(String query) async {
    setState(() {
      _searchQuery = query;
    });

    if (query.length < 3) {
      setState(() {
        _items = [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('items')
          .where('name', isGreaterThanOrEqualTo: query)
          .where(
            'name',
            isLessThanOrEqualTo: '$query\uf8ff',
          )
          .limit(50)
          .get();

      final items =
          snapshot.docs.map((doc) => AuctionItem.fromFirestore(doc)).toList();
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка поиска: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(onSearchChanged: _searchItems),
      body: Row(
        children: [
          CategoryPanel(isTokenLoading: _isTokenPriceLoading),
          const VerticalDivider(width: 2, thickness: 2, color: Colors.black),
          Expanded(
            child: AuctionListPanel(
              items: _items,
              isLoading: _isLoading,
              searchQuery: _searchQuery,
            ),
          ),
        ],
      ),
    );
  }
}

class CustomAppBar extends StatefulWidget implements PreferredSizeWidget {
  final ValueChanged<String> onSearchChanged;
  const CustomAppBar({super.key, required this.onSearchChanged});

  @override
  State<CustomAppBar> createState() => _CustomAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(65.0);
}

class _CustomAppBarState extends State<CustomAppBar> {
  bool _isBlizzardLoading = false;

  Future<void> _showConfirmationDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Подтверждение'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Вы уверены, что хотите загрузить данные?'),
                SizedBox(height: 10),
                Text(
                  'Загрузка может занять несколько минут.',
                  style: TextStyle(
                      fontStyle: FontStyle.italic, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('Загрузить'),
              onPressed: () {
                Navigator.of(context).pop();
                _fetchAndStoreBlizzardItems();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _fetchAndStoreBlizzardItems() async {
    setState(() => _isBlizzardLoading = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Загрузка данных с Blizzard API началась...')),
      );
    }

    try {
      final items = await BlizzardApiService().fetchItemsFromBlizzard();
      final collection = FirebaseFirestore.instance.collection('items');
      final batch = FirebaseFirestore.instance.batch();

      for (var item in items) {
        batch.set(collection.doc(item.id.toString()), item.toFirestore());
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${items.length} предметов успешно загружено!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при загрузке: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isBlizzardLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF1E3A8A),
      foregroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    );

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          children: [
            TextButton(
              onPressed: () => router.go('/favorites'),
              child: const Text('Избранное',
                  style: TextStyle(color: Color(0xFFD4BF7A), fontSize: 16)),
            ),
            const SizedBox(width: 20),
            TextButton(
              onPressed: () => router.go('/farms'),
              child: const Text('Фармы',
                  style: TextStyle(color: Color(0xFFD4BF7A), fontSize: 16)),
            ),
            const SizedBox(width: 20),
            const SizedBox(width: 20),
            TextButton(
              onPressed: () => router.go('/farms2'),
              child: const Text('Фармы 2.0',
                  style: TextStyle(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold)),
            ),

            const Spacer(),
            Expanded(
              flex: 2,
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF4A4A4A)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: TextField(
                    onChanged: widget.onSearchChanged,
                    decoration: const InputDecoration(
                      icon: Icon(Icons.search, size: 20),
                      hintText: 'Поиск по названию...',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            if (_isBlizzardLoading)
              const CircularProgressIndicator()
            else
              ElevatedButton.icon(
                onPressed: _showConfirmationDialog,
                icon: const Icon(Icons.cloud_download, size: 18),
                label: const Text('Загрузить предметы'),
                style: buttonStyle,
              ),
          ],
        ),
      ),
    );
  }
}

class CategoryPanel extends StatelessWidget {
  final bool isTokenLoading;
  const CategoryPanel({super.key, required this.isTokenLoading});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: 250,
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Жетон WoW', style: textTheme.titleMedium),
          const SizedBox(height: 12),
          if (isTokenLoading)
            const Center(child: CircularProgressIndicator())
          else
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('settings')
                  .doc('wow_token_price')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Text('Цена жетона не найдена.',
                      style: TextStyle(color: Colors.grey));
                }

                final docData = snapshot.data!.data() as Map<String, dynamic>?;
                final prices = docData?['prices'] as Map<String, dynamic>?;

                if (prices == null || prices.isEmpty) {
                  return const Text('Нет данных о цене жетона.',
                      style: TextStyle(color: Colors.grey));
                }

                final sortedKeys = prices.keys.toList()..sort();
                final latestTimestampKey = sortedKeys.last;
                final latestPrice = prices[latestTimestampKey];

                final formattedPrice =
                    NumberFormat("#,##0", "en_US").format(latestPrice);

                final List<FlSpot> spots = [];
                double minY = double.maxFinite;
                double maxY = double.minPositive;

                for (var i = 0; i < sortedKeys.length; i++) {
                  final key = sortedKeys[i];
                  final value = prices[key];
                  if (value != null) {
                    final doubleValue = value.toDouble();
                    spots.add(FlSpot(i.toDouble(), doubleValue));
                    if (doubleValue < minY) minY = doubleValue;
                    if (doubleValue > maxY) maxY = doubleValue;
                  }
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$formattedPrice g',
                        style: textTheme.bodyLarge?.copyWith(
                            fontSize: 20, color: Colors.greenAccent)),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 100,
                      child: LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: false),
                          titlesData: const FlTitlesData(
                            leftTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            rightTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            topTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                          lineTouchData: LineTouchData(
                            touchTooltipData: LineTouchTooltipData(
                              fitInsideHorizontally: true,
                              getTooltipItems:
                                  (List<LineBarSpot> touchedBarSpots) {
                                return touchedBarSpots
                                    .map((barSpot) {
                                      final spotIndex = barSpot.spotIndex;
                                      if (spotIndex < 0 ||
                                          spotIndex >= sortedKeys.length) {
                                        return null;
                                      }

                                      final date = DateFormat('yyyy-MM-dd HH')
                                          .parse(sortedKeys[spotIndex]);
                                      final price = barSpot.y.toInt();

                                      return LineTooltipItem(
                                        '${DateFormat.yMMMd().format(date)}\n${NumberFormat("#,##0", "en_US").format(price)} g',
                                        const TextStyle(
                                            color: Colors.white, fontSize: 12),
                                      );
                                    })
                                    .where((item) => item != null)
                                    .toList()
                                    .cast<LineTooltipItem>();
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
                              color: Colors.greenAccent,
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
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class AuctionListPanel extends StatelessWidget {
  final List<AuctionItem> items;
  final bool isLoading;
  final String searchQuery;

  const AuctionListPanel({
    super.key,
    required this.items,
    required this.isLoading,
    required this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          _buildHeader(Theme.of(context)),
          const Divider(color: Colors.grey),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('favorites')
                  .snapshots(),
              builder: (context, favSnapshot) {
                if (favSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final favoriteIds =
                    favSnapshot.data?.docs.map((doc) => doc.id).toSet() ?? {};

                if (isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (searchQuery.length < 3) {
                  return const Center(
                    child:
                        Text('Введите 3 или более символов для начала поиска.'),
                  );
                }

                if (items.isEmpty) {
                  return const Center(child: Text('Предметы не найдены'));
                }

                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isFavorited =
                        favoriteIds.contains(item.id.toString());

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 10.0),
                      child: Row(
                        key: ValueKey(item.id),
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: const Color(0xFFD4BF7A), width: 1.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: item.iconUrl != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(3.0),
                                    child: Image.network(
                                      item.iconUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) =>
                                          const Icon(Icons.error, size: 20),
                                    ),
                                  )
                                : const Icon(Icons.inventory_2, size: 20),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(item.name,
                                style: Theme.of(context).textTheme.bodyLarge),
                          ),
                          GestureDetector(
                            onTap: () =>
                                _toggleFavorite(context, item, isFavorited),
                            child: Container(
                              width: 40,
                              height: 40,
                              color: Colors.transparent,
                              alignment: Alignment.center,
                              child: Tooltip(
                                message: isFavorited
                                    ? 'Удалить из избранного'
                                    : 'Добавить в избранное',
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  transitionBuilder: (Widget child,
                                      Animation<double> animation) {
                                    return FadeTransition(
                                        opacity: animation, child: child);
                                  },
                                  child: Icon(
                                    isFavorited
                                        ? Icons.star
                                        : Icons.star_border,
                                    color: isFavorited
                                        ? const Color(0xFFFFC700)
                                        : const Color(0xFFD4BF7A),
                                    size: 24,
                                    key: ValueKey<bool>(isFavorited),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _toggleFavorite(
      BuildContext context, AuctionItem item, bool isFavorited) {
    final collection = FirebaseFirestore.instance.collection('favorites');
    final docId = item.id.toString();

    if (isFavorited) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Подтверждение'),
            content: Text(
                'Вы уверены, что хотите удалить "${item.name}" из избранного?'),
            actions: <Widget>[
              TextButton(
                child: const Text('Отмена'),
                onPressed: () => Navigator.of(context).pop(),
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

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        children: [
          Expanded(
              child: Text('Название предмета',
                  style: theme.textTheme.titleMedium)),
          const SizedBox(width: 40), // For the star icon
        ],
      ),
    );
  }
}
