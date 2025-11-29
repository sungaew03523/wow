
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// --- Модель данных для фарма ---
class Farm {
  final String id;
  final String name;
  final String profession;
  final String formula;
  final Timestamp createdAt;

  Farm({
    required this.id,
    required this.name,
    required this.profession,
    required this.formula,
    required this.createdAt,
  });

  factory Farm.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data()! as Map<String, dynamic>;
    return Farm(
      id: doc.id,
      name: data['name'] ?? 'Без названия',
      profession: data['profession'] ?? 'Нет профессии',
      formula: data['formula'] ?? '',
      createdAt: data['createdAt'] ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'profession': profession,
      'formula': formula,
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

  // --- Показать диалог для добавления нового фарма ---
  Future<void> _showAddFarmDialog() async {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final TextEditingController nameController = TextEditingController();
    final TextEditingController formulaController = TextEditingController();
    String? selectedProfession;

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Добавить новый фарм'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Профессия'),
                    items: _professions.map((String profession) {
                      return DropdownMenuItem<String>(
                        value: profession,
                        child: Text(profession),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      selectedProfession = newValue;
                    },
                    validator: (value) => value == null ? 'Выберите профессию' : null,
                  ),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Название фарма'),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Введите название' : null,
                  ),
                  TextFormField(
                    controller: formulaController,
                    decoration: const InputDecoration(labelText: 'Формула крафта'),
                    maxLines: 3,
                     validator: (value) =>
                        value == null || value.isEmpty ? 'Введите формулу' : null,
                  ),
                ],
              ),
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
              child: const Text('Добавить'),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  _addFarm(
                    nameController.text,
                    selectedProfession!,
                    formulaController.text,
                  );
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  // --- Добавить фарм в Firestore ---
  Future<void> _addFarm(
      String name, String profession, String formula) async {
    try {
      await _firestore.collection('farms').add({
        'name': name,
        'profession': profession,
        'formula': formula,
        'createdAt': Timestamp.now(),
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Ошибка при добавлении фарма: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  // --- Удалить фарм из Firestore ---
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
              child: const Text('Удалить', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await _firestore.collection('farms').doc(farmId).delete();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Фарм успешно удален.'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Ошибка при удалении фарма: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Фармы'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          tooltip: 'На главную',
          onPressed: () => context.go('/'),
        ),
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
            padding: const EdgeInsets.all(8.0),
            itemCount: farmDocs.length,
            itemBuilder: (context, index) {
              final farm = Farm.fromFirestore(farmDocs[index]);
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6.0),
                child: ListTile(
                  title:
                      Text(farm.name, style: Theme.of(context).textTheme.titleMedium),
                  subtitle: Text(farm.profession, style: const TextStyle(color: Colors.grey)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                    tooltip: 'Удалить фарм',
                    onPressed: () => _deleteFarm(farm.id),
                  ),
                  onTap: () {
                    // TODO: Переход на детальную страницу фарма
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddFarmDialog,
        tooltip: 'Добавить фарм',
        child: const Icon(Icons.add),
      ),
    );
  }
}
