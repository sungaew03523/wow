import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:function_tree/function_tree.dart';
import 'package:google_fonts/google_fonts.dart';

import '../blizzard_api_service.dart';

import '../models/auction_item.dart';

class RecipeComponent {
  final List<RecipeItem> options; // Список альтернатив (количество + имя)

  RecipeComponent({required this.options});
}

class RecipeItem {
  final String itemName;
  final String iconUrl;
  String quantity;

  RecipeItem({required this.itemName, this.iconUrl = '', this.quantity = '1'});
}

// --- Модель данных для Фарма v2 ---
class Farm2 {
  final String id;
  final String name; // Имя фарма (например, "Фарм руды")
  final String itemName; // Название крафта (например, "Алмазное кольцо")
  final String profession;
  final String costsFormula; // Формула затрат (например: 3*"Алмаз")
  final String revenueFormula; // Формула дохода (например: 1*"Пыль")
  final double resourcefulness; // % шанс Находчивости
  final double multicraft; // % шанс Мультикрафта
  final double resSavings; // % экономии от Находчивости (0.0-1.0)
  final double multiYield; // % дополнительного выхода от Мультикрафта (0.0-1.0)
  final String? iconUrl;
  final Timestamp createdAt;

  Farm2({
    this.id = '',
    required this.name,
    required this.itemName,
    required this.profession,
    required this.costsFormula,
    required this.revenueFormula,
    required this.resourcefulness,
    required this.multicraft,
    this.resSavings = 0.3, // Default value
    this.multiYield = 0.5, // Default value
    this.iconUrl,
    required this.createdAt,
  });

  factory Farm2.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data()! as Map<String, dynamic>;
    return Farm2(
      id: doc.id,
      name: data['name'] ?? '',
      itemName: data['itemName'] ?? '',
      profession: data['profession'] ?? '',
      costsFormula: data['costsFormula'] ?? '',
      revenueFormula: data['revenueFormula'] ?? '',
      resourcefulness: (data['resourcefulness'] ?? 0.0).toDouble(),
      multicraft: (data['multicraft'] ?? 0.0).toDouble(),
      resSavings: (data['resSavings'] ?? 0.3).toDouble(), // New field
      multiYield: (data['multiYield'] ?? 0.5).toDouble(), // New field
      iconUrl: data['iconUrl'],
      createdAt: data['createdAt'] ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'itemName': itemName,
      'profession': profession,
      'costsFormula': costsFormula,
      'revenueFormula': revenueFormula,
      'resourcefulness': resourcefulness,
      'multicraft': multicraft,
      'resSavings': resSavings,
      'multiYield': multiYield,
      'iconUrl': iconUrl,
      'createdAt': createdAt,
    };
  }
}

class Farms2Screen extends StatefulWidget {
  const Farms2Screen({super.key});

  @override
  State<Farms2Screen> createState() => _Farms2ScreenState();
}

class _Farms2ScreenState extends State<Farms2Screen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isPriceUpdating = false;
  Map<String, double> _overrides = {}; // Храним ручные цены в памяти экрана


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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Фармы v2.0', style: GoogleFonts.oswald(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => context.go('/'),
        ),
        actions: [
          if (_overrides.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                final bool? confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Сброс цен'),
                    content: const Text('Вы уверены, что хотите сбросить все ручные правки цен?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                      ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Сбросить')),
                    ],
                  ),
                );
                if (confirm == true) {
                  setState(() => _overrides = {});
                }
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Сбросить ручные цены'),
              style: TextButton.styleFrom(foregroundColor: Colors.orangeAccent),
            ),
          _isPriceUpdating
              ? const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _handleFullUpdate,
                  tooltip: 'Обновить цены',
                ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('favorites').snapshots(),
        builder: (context, favSnapshot) {
          if (!favSnapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final favoritesMap = {
            for (var doc in favSnapshot.data!.docs)
              (doc.data() as Map<String, dynamic>)['name'] as String: AuctionItem.fromFirestore(doc)
          };

          return StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('farms2').orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Center(child: Text('Ошибка загрузки'));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

              final farms = snapshot.data!.docs.map((doc) => Farm2.fromFirestore(doc)).toList();

              if (farms.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.agriculture, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('Фармов пока нет. Создайте первый!', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 24),
                      ElevatedButton(onPressed: () => _showFarmDialog(), child: const Text('Создать Фарм')),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: farms.length,
                itemBuilder: (context, index) => Farm2Card(
                  farm: farms[index], 
                  favorites: favoritesMap,
                  overrides: _overrides,
                  onEdit: () => _showFarmDialog(farm: farms[index]),
                  onDuplicate: () => _duplicateFarm(farms[index]),
                  onOverrideChanged: (name, price) {
                    setState(() {
                      if (price == null) {
                        _overrides.remove(name);
                      } else {
                        _overrides[name] = price;
                      }
                    });
                  },
                ),

              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showFarmDialog(),
        label: const Text('Новый Фарм'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  List<RecipeComponent> _parseFormula(String formula, Map<String, AuctionItem> favorites) {
    if (formula.trim().isEmpty) return [];
    
    final List<RecipeComponent> components = [];
    
    // Ищем все вхождения предметов в формате: кол*"Имя"
    // Мы предполагаем, что если предметы находятся внутри блока min(), они относятся к одному компоненту (альтернативы)
    // Если же они разделены знаком "+", это разные компоненты.
    
    final RegExp componentRegex = RegExp(r'(\d+(?:\.\d+)?|\([^)]+\))\*\"([^\"]+)\"');
    
    // Разделяем по знаку "+", стараясь не разбить содержимое min()
    // Это упрощенная логика: мы просто ищем все части, разделенные "+"
    final List<String> parts = _splitByPlusOutsideMin(formula);
    
    for (var part in parts) {
      final matches = componentRegex.allMatches(part).toList();
      if (matches.isNotEmpty) {
        final List<RecipeItem> options = matches.map((m) {
          final String name = m.group(2) ?? '';
          return RecipeItem(
            itemName: name,
            quantity: m.group(1) ?? '1',
            iconUrl: favorites[name]?.iconUrl ?? '',
          );
        }).toList();
        components.add(RecipeComponent(options: options));
      }
    }
    
    return components;
  }

  List<String> _splitByPlusOutsideMin(String formula) {
    final List<String> result = [];
    int level = 0;
    int lastStart = 0;
    
    for (int i = 0; i < formula.length; i++) {
      if (formula[i] == '(') level++;
      if (formula[i] == ')') level--;
      if (formula[i] == '+' && level == 0) {
        result.add(formula.substring(lastStart, i).trim());
        lastStart = i + 1;
      }
    }
    result.add(formula.substring(lastStart).trim());
    return result;
  }


  String _generateFormula(List<RecipeComponent> components) {
    if (components.isEmpty) return '0';
    return components.map((c) {
      if (c.options.length > 1) {
        // Каскадный min(a, min(b, min(c, ...))) для поддержки любого количества альтернатив
        String result = '${c.options.last.quantity}*"${c.options.last.itemName}"';
        for (int i = c.options.length - 2; i >= 0; i--) {
          final o = c.options[i];
          result = 'min(${o.quantity}*"${o.itemName}", $result)';
        }
        return result;
      } else {
        return '${c.options.first.quantity}*"${c.options.first.itemName}"';
      }
    }).join(' + ');
  }


  Future<void> _showFarmDialog({Farm2? farm}) async {
    // Получаем текущую карту избранного для поиска иконок и имен
    final favoritesSnapshot = await _firestore.collection('favorites').get();
    final Map<String, AuctionItem> favoritesMap = {
      for (var doc in favoritesSnapshot.docs) doc.id: AuctionItem.fromFirestore(doc)
    };

    final nameController = TextEditingController(text: farm?.name);
    final itemNameController = TextEditingController(text: farm?.itemName);
    double resValue = farm?.resourcefulness ?? 0.0;
    double resSavings = farm?.resSavings ?? 0.3;
    double multiValue = farm?.multicraft ?? 0.0;
    double multiYieldVal = farm?.multiYield ?? 0.5;
    String? selectedProfession = farm?.profession ?? _professions.first;

    // Списки компонентов
    List<RecipeComponent> costs = _parseFormula(farm?.costsFormula ?? '', favoritesMap);
    List<RecipeComponent> revenue = _parseFormula(farm?.revenueFormula ?? '', favoritesMap);

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget buildPickerTile(AuctionItem item, StateSetter dialogState, List<RecipeComponent> list, [RecipeComponent? parent]) {
            return ListTile(
              leading: item.iconUrl != null ? Image.network(item.iconUrl!, width: 24) : null,
              title: Text(item.name),
              onTap: () {
                dialogState(() {
                  if (parent != null) {
                    final baseQuantity = parent.options.isNotEmpty ? parent.options.first.quantity : '1';
                    parent.options.add(RecipeItem(itemName: item.name, iconUrl: item.iconUrl ?? '', quantity: baseQuantity));
                  } else {
                    list.add(RecipeComponent(options: [RecipeItem(itemName: item.name, iconUrl: item.iconUrl ?? '')]));
                  }
                });
                Navigator.pop(context);
              },
            );
          }

          void showPicker(List<RecipeComponent> list, [RecipeComponent? parent]) {
            final matchingItems = favoritesMap.values.where((item) => item.professions.contains(selectedProfession)).toList();
            final otherItems = favoritesMap.values.where((item) => !item.professions.contains(selectedProfession)).toList();

            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Добавить предмет'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (matchingItems.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text('ДЛЯ $selectedProfession'.toUpperCase(), 
                              style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        ...matchingItems.map((item) => buildPickerTile(item, setDialogState, list, parent)),
                        const Divider(),
                      ],
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('ВСЕ ПРЕДМЕТЫ', 
                            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      ...otherItems.map((item) => buildPickerTile(item, setDialogState, list, parent)),
                    ],
                  ),
                ),
              ),
            );
          }

          Widget buildComponentRow(RecipeComponent comp, List<RecipeComponent> list) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...comp.options.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        if (idx > 0) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('ИЛИ', style: TextStyle(fontSize: 10, color: Colors.orangeAccent))),
                        if (item.iconUrl.isNotEmpty) Image.network(item.iconUrl, width: 24, height: 24) else const Icon(Icons.inventory_2, size: 24),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: Text(item.itemName, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 35,
                            child: TextField(
                              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                              style: const TextStyle(fontSize: 12),
                              onChanged: (v) => item.quantity = v,
                              controller: TextEditingController(text: item.quantity)..selection = TextSelection.fromPosition(TextPosition(offset: item.quantity.length)),
                            ),
                          ),
                        ),
                        if (idx == 0)
                          IconButton(
                            icon: const Icon(Icons.add_link, color: Colors.orangeAccent, size: 20),
                            onPressed: () => showPicker(list, comp),
                            tooltip: 'Добавить альтернативу',
                          ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                          onPressed: () => setDialogState(() {
                            if (comp.options.length > 1) {
                              comp.options.removeAt(idx);
                            } else {
                              list.remove(comp);
                            }
                          }),
                        ),
                      ],
                    ),
                  );
                }),
                const Divider(color: Colors.white10),
              ],
            );
          }


          return AlertDialog(
            title: Text(farm == null ? 'Новый Фарм 2.0' : 'Редактировать Фарм'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Название группы/фарма')),
                    TextField(controller: itemNameController, decoration: const InputDecoration(labelText: 'Название крафта (предмета)')),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedProfession,
                            items: _professions.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                            onChanged: (v) => setDialogState(() => selectedProfession = v),
                            decoration: const InputDecoration(labelText: 'Профессия'),
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Затраты (Реагенты)', style: GoogleFonts.oswald(color: Colors.redAccent, fontSize: 16)),
                    ...costs.map((c) => buildComponentRow(c, costs)),
                    TextButton.icon(onPressed: () => showPicker(costs), icon: const Icon(Icons.add, size: 16), label: const Text('Добавить затрату')),
                    
                    const SizedBox(height: 16),
                    Text('Выручка (Что получим)', style: GoogleFonts.oswald(color: Colors.blueAccent, fontSize: 16)),
                    ...revenue.map((c) => buildComponentRow(c, revenue)),
                    TextButton.icon(onPressed: () => showPicker(revenue), icon: const Icon(Icons.add, size: 16), label: const Text('Добавить доход')),
                    
                    const Divider(),
                    Text('Находчивость: ${resValue.toInt()}% (Экономия: ${(resSavings * 100).toInt()}%)', style: const TextStyle(fontSize: 12)),
                    Slider(value: resValue, min: 0, max: 100, divisions: 100, onChanged: (v) => setDialogState(() => resValue = v)),
                    Slider(value: resSavings, min: 0, max: 1.0, divisions: 100, onChanged: (v) => setDialogState(() => resSavings = v)),
                    const SizedBox(height: 8),
                    Text('Мультикрафт: ${multiValue.toInt()}% (Бонус: ${(multiYieldVal * 100).toInt()}%)', style: const TextStyle(fontSize: 12)),
                    Slider(value: multiValue, min: 0, max: 100, divisions: 100, onChanged: (v) => setDialogState(() => multiValue = v)),
                    Slider(value: multiYieldVal, min: 0, max: 2.0, divisions: 200, onChanged: (v) => setDialogState(() => multiYieldVal = v)),

                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
              ElevatedButton(
                onPressed: () async {
                  final data = {
                    'name': nameController.text,
                    'itemName': itemNameController.text,
                    'profession': selectedProfession,
                    'costsFormula': _generateFormula(costs),
                    'revenueFormula': _generateFormula(revenue),
                    'resourcefulness': resValue,
                    'resSavings': resSavings,
                    'multicraft': multiValue,
                    'multiYield': multiYieldVal,
                    'createdAt': farm?.createdAt ?? Timestamp.now(),
                  };
                  if (farm == null) {
                    await _firestore.collection('farms2').add(data);
                  } else {
                    await _firestore.collection('farms2').doc(farm.id).update(data);
                  }
                  if (!mounted) return;
                  Navigator.pop(context);
                },
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      ),
    );
  }
  Future<void> _duplicateFarm(Farm2 farm) async {
    try {
      final Map<String, dynamic> data = farm.toFirestore();
      final String originalName = farm.name.isNotEmpty ? farm.name : farm.itemName;
      data['name'] = '$originalName (копия)';
      data['createdAt'] = Timestamp.now();
      
      await _firestore.collection('farms2').add(data);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Фарм успешно дублирован.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка дублирования: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  Future<void> _handleFullUpdate() async {
    setState(() => _isPriceUpdating = true);
    try {
      final favoritesSnapshot = await _firestore.collection('favorites').get();
      final itemsToUpdate = {
        for (var doc in favoritesSnapshot.docs)
          doc.id: (doc.data()['analysisVolume'] ?? 1000) as int,
      };
      if (itemsToUpdate.isNotEmpty) {
        await BlizzardApiService().fetchReagentPrices(itemsToUpdate);
      }
    } finally {
      if (mounted) setState(() => _isPriceUpdating = false);
    }
  }
}

class Farm2Card extends StatelessWidget {
  final Farm2 farm;
  final Map<String, AuctionItem> favorites;
  final Map<String, double> overrides;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final Function(String itemName, double? newPrice) onOverrideChanged;

  const Farm2Card({
    super.key, 
    required this.farm, 
    required this.favorites, 
    required this.overrides,
    required this.onEdit,
    required this.onDuplicate,
    required this.onOverrideChanged,
  });


  @override
  Widget build(BuildContext context) {
    final double baseCost = _calculateFormula(farm.costsFormula, favorites, overrides);
    final double baseRevenue = _calculateFormula(farm.revenueFormula, favorites, overrides) * 0.95;

    // Находчивость экономит N% реагентов при срабатывании (N = farm.resSavings)
    final double avgCostSavings = (farm.resourcefulness / 100.0) * farm.resSavings;
    final double effectiveCost = baseCost * (1 - avgCostSavings);

    // Мультикрафт дает в среднем N% к выходу при срабатывании (N = farm.multiYield)
    final double avgRevenueBonus = (farm.multicraft / 100.0) * farm.multiYield;
    final double effectiveRevenue = baseRevenue * (1 + avgRevenueBonus);

    final double resGain = baseCost - effectiveCost;
    final double multiGain = effectiveRevenue - baseRevenue;
    final double baseProfit = baseRevenue - baseCost;
    final double profitPerCraft = effectiveRevenue - effectiveCost;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 8,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: const BorderSide(color: Color(0xFFD4BF7A), width: 1),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF2C2C2C),
              const Color(0xFF1A1A1A),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(farm.itemName.isNotEmpty ? farm.itemName : farm.name, 
                                style: GoogleFonts.oswald(fontSize: 20, color: const Color(0xFFD4BF7A), fontWeight: FontWeight.bold, letterSpacing: 1)),
                            ),
                            Row(
                              children: [
                                IconButton(icon: const Icon(Icons.copy, color: Colors.green, size: 18), onPressed: onDuplicate, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                                const SizedBox(width: 8),
                                IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 18), onPressed: onEdit, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                                const SizedBox(width: 8),
                                IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18), onPressed: () async {
                                  final bool? confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Подтверждение удаления'),
                                      content: const Text('Вы уверены, что хотите удалить этот фарм?'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                                          child: const Text('Удалить'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await FirebaseFirestore.instance.collection('farms2').doc(farm.id).delete();
                                  }
                                }, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Text(farm.profession, style: const TextStyle(color: Colors.white60, fontSize: 13)),
                            if (farm.name.isNotEmpty && farm.itemName.isNotEmpty)
                              Text(' • ${farm.name}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            const Spacer(),
                            Tooltip(
                              message: 'Базовая прибыль: ${baseProfit.toStringAsFixed(0)}з\nНаходчивость: +${resGain.toStringAsFixed(0)}з\nМультикрафт: +${multiGain.toStringAsFixed(0)}з\n(Нажмите для подробного расчета)',
                              child: InkWell(
                                onTap: () => _showCalculationDetails(context, favorites, overrides),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  child: Icon(Icons.calculate_outlined, size: 16, color: Color(0xFFD4BF7A)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF4A4A4A), height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ПРИБЫЛЬ ЗА КРАФТ', style: TextStyle(color: Color(0xFFD4BF7A), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 2),
                      Text('${profitPerCraft.toStringAsFixed(2)} з', 
                        style: TextStyle(color: profitPerCraft > 0 ? Colors.greenAccent : Colors.redAccent, fontSize: 26, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Row(
                    children: [
                      _buildStatBadge(Icons.auto_fix_high, '${farm.resourcefulness.toInt()}%'),
                      const SizedBox(width: 6),
                      _buildStatBadge(Icons.layers, '${farm.multicraft.toInt()}%'),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 12),
              _buildComponentsSection(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatBadge(IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFD4BF7A), width: 0.5)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFD4BF7A)),
          const SizedBox(width: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _showCalculationDetails(BuildContext context, Map<String, AuctionItem> favorites, Map<String, double> overrides) {
    // Вычисляем базовые значения для отладки
    final double baseCost = _calculateFormula(farm.costsFormula, favorites, overrides);
    final double baseRevenue = _calculateFormula(farm.revenueFormula, favorites, overrides) * 0.95;

    // Собираем отладочную информацию
    String costsDebug = farm.costsFormula;
    final costItems = _extractItemNames(farm.costsFormula);
    for (var name in costItems) {
      double p = overrides[name] ?? favorites[name]?.weightedAveragePrice ?? 0.0;
      costsDebug = costsDebug.replaceAll('"$name"', p.toStringAsFixed(1));
    }

    String revDebug = farm.revenueFormula;
    final revItems = _extractItemNames(farm.revenueFormula);
    for (var name in revItems) {
      double p = overrides[name] ?? favorites[name]?.weightedAveragePrice ?? 0.0;
      revDebug = revDebug.replaceAll('"$name"', p.toStringAsFixed(1));
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Детали расчета', style: TextStyle(color: Color(0xFFD4BF7A))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ЗАТРАТЫ:', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
            Text(costsDebug, style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.white70)),
            const SizedBox(height: 8),
            const Text('ДОХОД (с учётом -5% комиссии):', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
            Text(revDebug, style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.white70)),
            const Divider(color: Colors.white10, height: 24),
            _buildDebugRow('Шанс Находчивости', '${farm.resourcefulness.toInt()}%'),
            _buildDebugRow('Множитель Находчивости', 'x${(1 - (farm.resourcefulness / 100 * farm.resSavings)).toStringAsFixed(3)}'),
            const SizedBox(height: 4),
            _buildDebugRow('Шанс Мультикрафта', '${farm.multicraft.toInt()}%'),
            _buildDebugRow('Множитель Мультикрафта', 'x${(1 + (farm.multicraft / 100 * farm.multiYield)).toStringAsFixed(3)}'),
            const Divider(color: Colors.white10, height: 24),
            const Text('ИТОГОВАЯ МАТЕМАТИКА (за 1 крафт):', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            _buildDebugRow('Эфф. Выручка', '${(baseRevenue * (1 + (farm.multicraft / 100 * farm.multiYield))).toStringAsFixed(1)} з'),
            _buildDebugRow('Эфф. Затраты', '- ${(baseCost * (1 - (farm.resourcefulness / 100 * farm.resSavings))).toStringAsFixed(1)} з'),
            const Divider(color: Color(0xFFD4BF7A), thickness: 1),
            _buildDebugRow('Прибыль за крафт', '${((baseRevenue * (1 + (farm.multicraft / 100 * farm.multiYield))) - (baseCost * (1 - (farm.resourcefulness / 100 * farm.resSavings)))).toStringAsFixed(2)} з', color: Colors.greenAccent),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Понятно')),
        ],
      ),
    );
  }

  Widget _buildDebugRow(String label, String value, {Color color = Colors.white}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  double _calculateFormula(String formula, Map<String, AuctionItem> favorites, [Map<String, double>? overrides]) {
    if (formula.trim().isEmpty) return 0.0;
    
    // 1. Извлекаем все названия предметов
    final itemNames = _extractItemNames(formula);
    String workingFormula = formula;
    
    // 2. Подставляем цены вместо названий предметов
    for (String name in itemNames) {
      double p = overrides?[name] ?? favorites[name]?.weightedAveragePrice ?? 0.0;
      workingFormula = workingFormula.replaceAll('"$name"', p.toString());
    }

    // 3. РУЧНОЙ РАСЧЕТ min(...) блоков, так как библиотеки часто на них ломаются
    // Мы находим самый внутренний min(a, b, c...), считаем его и подставляем результат
    final RegExp minRegex = RegExp(r'min\(([^()]+)\)');
    while (true) {
      final match = minRegex.firstMatch(workingFormula);
      if (match == null) break;
      
      final String innerContent = match.group(1)!;
      final parts = innerContent.split(',').map((s) {
        // Каждый аргумент внутри min может быть выражением (например, 3*599.5)
        // Считаем его через interpret()
        try {
          return s.trim().interpret().toDouble();
        } catch (_) {
          return 0.0;
        }
      }).toList();
      
      // Находим минимум среди вычисленных аргументов
      double minValue = parts.isEmpty ? 0.0 : parts[0];
      for (var val in parts) {
        if (val < minValue) minValue = val;
      }
      
      // Заменяем весь блок min(...) на вычисленное число
      workingFormula = workingFormula.replaceFirst(match.group(0)!, minValue.toString());
    }

    // 4. Финальный расчет оставшейся формулы (теперь там только сложения и числа)
    if (workingFormula.trim().isEmpty) return 0.0;
    
    // Безопасная очистка: убираем любые символы, которые interpret() может не понять 
    // (на случай ошибок в формуле)
    String safeFormula = workingFormula.replaceAll(RegExp(r'[^\d.+\-*/() ]'), '');
    if (safeFormula.trim().isEmpty) return 0.0;

    try {
      return safeFormula.interpret().toDouble();
    } catch (e) {
      debugPrint('Ошибка вычисления формулы ($safeFormula): $e');
      return 0.0;
    }
  }

  Widget _buildComponentsSection(BuildContext context) {
    final Set<String> costItems = _extractItemNames(farm.costsFormula);
    final Set<String> revenueItems = _extractItemNames(farm.revenueFormula);
    final Set<String> allItems = {...costItems, ...revenueItems};

    if (allItems.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: allItems.map((name) {
            // Чтобы корректно отобразить min() блоки, нам нужно проверить, является ли этот предмет частью такого блока
            // Но для упрощения в карточке мы можем просто вывести все участвующие предметы, 
            // а тот, который прямо сейчас выбран функцией min() для расчета, подсветить ярче.
            
            final item = favorites[name];
            final bool isOverridden = overrides.containsKey(name);
            final double price = isOverridden ? overrides[name]! : (item?.weightedAveragePrice ?? 0.0);
            
            // Находим минимальную цену среди всех альтернатив, если они есть
            // (Это упрощенная логика подсветки)
            
            return InkWell(
              onTap: () async {
                final TextEditingController controller = TextEditingController(text: price.toStringAsFixed(2));
                final double? result = await showDialog<double>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Цена для "$name"'),
                    content: TextField(
                      controller: controller,
                      decoration: const InputDecoration(labelText: 'Цена за 1 шт. (золото)', suffixText: 'з'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      autofocus: true,
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
                      if (isOverridden)
                        TextButton(onPressed: () => Navigator.pop(context, -1.0), child: const Text('Сброс', style: TextStyle(color: Colors.orange))),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, double.tryParse(controller.text.replaceAll(',', '.'))),
                        child: const Text('Применить'),
                      ),
                    ],
                  ),
                );

                if (result != null) {
                  onOverrideChanged(name, result < 0 ? null : result);
                }
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isOverridden ? Colors.blue.withAlpha(40) : Colors.black26,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isOverridden ? Colors.blueAccent : Colors.white10, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item?.iconUrl != null)
                      ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(item!.iconUrl!, width: 16, height: 16))
                    else
                      const Icon(Icons.inventory_2, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(name, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                    const SizedBox(width: 4),
                    Text('${price.toStringAsFixed(0)}з', style: TextStyle(fontSize: 11, color: isOverridden ? Colors.lightBlueAccent : Colors.greenAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
      ],
    );
  }


  Set<String> _extractItemNames(String formula) {
    final RegExp regex = RegExp(r'"([^"]+)"');
    return regex.allMatches(formula).map((m) => m.group(1)!).toSet();
  }
}
