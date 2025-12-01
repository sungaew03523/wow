
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../blizzard_api_service.dart';
import '../models/auction_item.dart';
import '../app_router.dart';


class AuctionHouseScreen extends StatefulWidget {
  const AuctionHouseScreen({super.key});

  @override
  State<AuctionHouseScreen> createState() => _AuctionHouseScreenState();
}

class _AuctionHouseScreenState extends State<AuctionHouseScreen> {
  List<AuctionItem> _items = [];
  bool _isLoading = false;
  String _searchQuery = '';

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
          .where('name', isLessThanOrEqualTo: '$query\uf8ff') // Correct Firestore prefix search
          .limit(50)
          .get();

      final items = snapshot.docs.map((doc) => AuctionItem.fromFirestore(doc)).toList();
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка поиска: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(onSearchChanged: _searchItems),
      body: Row(
        children: [
          const CategoryPanel(),
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
                  style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () {
                Navigator.of(context).pop();
              },
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Загрузка данных с Blizzard API началась...')),
    );

    try {
      final items = await BlizzardApiService().fetchItemsFromBlizzard();
      final collection = FirebaseFirestore.instance.collection('items');
      final batch = FirebaseFirestore.instance.batch();

      for (var item in items) {
        batch.set(collection.doc(item.id.toString()), item.toFirestore());
      }
      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${items.length} предметов успешно загружено!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при загрузке: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isBlizzardLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          children: [
            TextButton(
              onPressed: () => router.go('/favorites'),
              child: const Text('Избранное', style: TextStyle(color: Color(0xFFD4BF7A), fontSize: 16)),
            ),
            const SizedBox(width: 20),
            TextButton(
              onPressed: () => router.go('/farms'),
              child: const Text('Фармы', style: TextStyle(color: Color(0xFFD4BF7A), fontSize: 16)),
            ),
            const SizedBox(width: 20),
            Expanded(
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: CircularProgressIndicator(),
              )
            else
              ElevatedButton.icon(
                onPressed: _showConfirmationDialog,
                icon: const Icon(Icons.cloud_download, size: 18),
                label: const Text('Загрузить предметы'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A8A),
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CategoryPanel extends StatelessWidget {
  const CategoryPanel({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.all(12.0),
      child: const Center(
        child: Text(
          'Категории\n(скоро будут)',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
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
              stream: FirebaseFirestore.instance.collection('favorites').snapshots(),
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
                    child: Text('Введите 3 или более символов для начала поиска.'),
                  );
                }

                if (items.isEmpty) {
                  return const Center(child: Text('Предметы не найдены'));
                }

                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isFavorited = favoriteIds.contains(item.id.toString());

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
                                    child: Image.network(
                                      item.iconUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) => const Icon(Icons.error, size: 20),
                                    ),
                                  )
                                : const Icon(Icons.inventory_2, size: 20),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              item.name,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _toggleFavorite(context, item, isFavorited),
                            child: Container(
                              width: 40,
                              height: 40,
                              color: Colors.transparent,
                              alignment: Alignment.center,
                              child: Tooltip(
                                message: isFavorited ? 'Удалить из избранного' : 'Добавить в избранное',
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  transitionBuilder: (Widget child, Animation<double> animation) {
                                    return FadeTransition(opacity: animation, child: child);
                                  },
                                  child: Icon(
                                    isFavorited ? Icons.star : Icons.star_border,
                                    color: isFavorited ? const Color(0xFFFFC700) : const Color(0xFFD4BF7A),
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

  void _toggleFavorite(BuildContext context, AuctionItem item, bool isFavorited) {
    final collection = FirebaseFirestore.instance.collection('favorites');
    final docId = item.id.toString();

    if (isFavorited) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Подтверждение'),
            content: Text('Вы уверены, что хотите удалить "${item.name}" из избранного?'),
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

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        children: [
          Expanded(
            child: Text('Название предмета', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(width: 40), // For the star icon
        ],
      ),
    );
  }
}
