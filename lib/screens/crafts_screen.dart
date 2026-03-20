import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../blizzard_api_service.dart';
import '../models/wow_recipe.dart';


class CraftsScreen extends StatefulWidget {
  const CraftsScreen({super.key});

  @override
  State<CraftsScreen> createState() => _CraftsScreenState();
}

class _CraftsScreenState extends State<CraftsScreen> {
  List<WowRecipe> _recipes = [];
  bool _isLoading = false;
  String _searchQuery = '';

  Future<void> _searchRecipes(String query) async {
    setState(() {
      _searchQuery = query;
    });

    if (query.length < 3) {
      setState(() {
        _recipes = [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('recipes')
          .where('name', isGreaterThanOrEqualTo: query)
          .where(
            'name',
            isLessThanOrEqualTo: '$query\uf8ff',
          )
          .limit(50)
          .get();

      final recipes =
          snapshot.docs.map((doc) => WowRecipe.fromFirestore(doc)).toList();
      setState(() {
        _recipes = recipes;
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
      appBar: CraftsAppBar(onSearchChanged: _searchRecipes),
      body: Row(
        children: [
          Expanded(
            child: CraftsListPanel(
              recipes: _recipes,
              isLoading: _isLoading,
              searchQuery: _searchQuery,
            ),
          ),
        ],
      ),
    );
  }
}

class CraftsAppBar extends StatefulWidget implements PreferredSizeWidget {
  final ValueChanged<String> onSearchChanged;
  const CraftsAppBar({super.key, required this.onSearchChanged});

  @override
  State<CraftsAppBar> createState() => _CraftsAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(65.0);
}

class _CraftsAppBarState extends State<CraftsAppBar> {
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
                Text('Вы уверены, что хотите загрузить рецепты Midnight?'),
                SizedBox(height: 10),
                Text(
                  'Дождитесь завершения, это может занять минуту.',
                  style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
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
                _fetchAndStoreMidnightRecipes();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _fetchAndStoreMidnightRecipes() async {
    setState(() => _isBlizzardLoading = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Загрузка рецептов Midnight началась...')),
      );
    }

    try {
      await BlizzardApiService().downloadMidnightRecipesToFirestore();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Рецепты успешно загружены!'),
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
            IconButton(
              icon: const Icon(Icons.home),
              tooltip: 'На главную',
              onPressed: () => context.go('/'),
            ),
            const SizedBox(width: 20),
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
                      hintText: 'Поиск рецептов...',
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
                label: const Text('Загрузить Midnight Рецепты'),
                style: buttonStyle,
              ),
          ],
        ),
      ),
    );
  }
}

class CraftsListPanel extends StatelessWidget {
  final List<WowRecipe> recipes;
  final bool isLoading;
  final String searchQuery;

  const CraftsListPanel({
    super.key,
    required this.recipes,
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
              stream: FirebaseFirestore.instance.collection('favorite_crafts').snapshots(),
              builder: (context, favSnapshot) {
                if (favSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final favoriteIds = favSnapshot.data?.docs.map((doc) => doc.id).toSet() ?? {};

                if (isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (searchQuery.length < 3) {
                  return const Center(
                    child: Text('Введите 3 или более символов для поиска крафтов.'),
                  );
                }

                if (recipes.isEmpty) {
                  return const Center(child: Text('Рецепты не найдены.'));
                }

                return ListView.builder(
                  itemCount: recipes.length,
                  itemBuilder: (context, index) {
                    final recipe = recipes[index];
                    final isFavorited = favoriteIds.contains(recipe.id.toString());

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                      child: Row(
                        key: ValueKey(recipe.id),
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFD4BF7A), width: 1.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: recipe.iconUrl != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(3.0),
                                    child: Image.network(
                                      recipe.iconUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) => const Icon(Icons.error, size: 20),
                                    ),
                                  )
                                : const Icon(Icons.handyman, size: 20),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(recipe.name, style: Theme.of(context).textTheme.bodyLarge),
                                if (recipe.professionName != null)
                                  Text(
                                    recipe.professionName!,
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: recipe.reagents.map((reagent) {
                                return Text(
                                  '${reagent.name} x${reagent.quantity}', 
                                  style: const TextStyle(fontSize: 12),
                                );
                              }).toList(),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _toggleFavorite(context, recipe, isFavorited),
                            child: Container(
                              width: 40,
                              height: 40,
                              color: Colors.transparent,
                              alignment: Alignment.center,
                              child: Tooltip(
                                message: isFavorited ? 'Удалить из избранных крафтов' : 'Добавить в избранные крафты',
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

  void _toggleFavorite(BuildContext context, WowRecipe recipe, bool isFavorited) {
    final collection = FirebaseFirestore.instance.collection('favorite_crafts');
    final docId = recipe.id.toString();

    if (isFavorited) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Подтверждение'),
            content: Text('Вы уверены, что хотите удалить рецепт "${recipe.name}" из избранного?'),
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
      collection.doc(docId).set(recipe.toFirestore());
    }
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        children: [
          const SizedBox(width: 52),
          Expanded(child: Text('Название рецепта', style: theme.textTheme.titleMedium)),
          Expanded(flex: 1, child: Text('Реагенты', style: theme.textTheme.titleMedium)),
          const SizedBox(width: 40), 
        ],
      ),
    );
  }
}
