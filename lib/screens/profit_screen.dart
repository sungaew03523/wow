import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_router.dart';

class ProfitScreen extends StatefulWidget {
  const ProfitScreen({super.key});

  @override
  State<ProfitScreen> createState() => _ProfitScreenState();
}

class _ProfitScreenState extends State<ProfitScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    final Color primaryTextColor = const Color(0xFFD4BF7A);

    return Scaffold(
      appBar: AppBar(
        title: Text('Учет Прибыли', style: GoogleFonts.oswald(color: primaryTextColor, fontSize: 24)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => router.go('/'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: 'Добавить персонажа',
            onPressed: () => _showAddCharacterDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('characters').orderBy('name').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Ошибка: ${snapshot.error}'));
          }
          
          final characters = snapshot.data?.docs ?? [];
          
          if (characters.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Icon(Icons.people_outline, size: 64, color: primaryTextColor.withAlpha(100)),
                   const SizedBox(height: 16),
                   const Text('Персонажи пока не добавлены', style: TextStyle(color: Colors.grey)),
                   const SizedBox(height: 24),
                   ElevatedButton.icon(
                     onPressed: () => _showAddCharacterDialog(context),
                     icon: const Icon(Icons.add),
                     label: const Text('Добавить первого персонажа'),
                   ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: characters.length,
            itemBuilder: (context, index) {
              final charDoc = characters[index];
              final charData = charDoc.data() as Map<String, dynamic>;
              final name = charData['name'] ?? 'Без имени';
              final totalProfit = (charData['totalProfit'] ?? 0).toDouble();

              return _CharacterCard(
                docId: charDoc.id,
                name: name,
                totalProfit: totalProfit,
                onAddProfit: () => _showAddProfitDialog(context, charDoc.id, name),
                onShowLogs: () => _showLogsDialog(context, charDoc.id, name),
                onDelete: () => _showDeleteConfirmation(context, charDoc.id, name),
              );
            },
          );
        },
      ),
    );
  }

  void _showAddCharacterDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить персонажа'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Имя персонажа'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await _firestore.collection('characters').add({
                  'name': controller.text.trim(),
                  'totalProfit': 0,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  void _showAddProfitDialog(BuildContext context, String charId, String charName) {
    final TextEditingController amountController = TextEditingController();
    final TextEditingController noteController = TextEditingController();
    final TextEditingController whoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Добавить прибыль: $charName'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                decoration: const InputDecoration(labelText: 'Сумма (золото)', hintText: '0'),
                keyboardType: TextInputType.number,
                autofocus: true,
              ),
              TextField(
                controller: whoController,
                decoration: const InputDecoration(labelText: 'Кто внес', hintText: 'Ваше имя'),
              ),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Комментарий', hintText: 'Например: Фарм руды'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text) ?? 0;
              if (amount > 0) {
                final batch = _firestore.batch();
                
                // Add log entry
                final logRef = _firestore.collection('profit_logs').doc();
                batch.set(logRef, {
                  'characterId': charId,
                  'charName': charName,
                  'amount': amount,
                  'timestamp': FieldValue.serverTimestamp(),
                  'note': noteController.text.trim(),
                  'who': whoController.text.trim().isEmpty ? 'Аноним' : whoController.text.trim(),
                });
                
                // Update character total
                final charRef = _firestore.collection('characters').doc(charId);
                batch.update(charRef, {
                  'totalProfit': FieldValue.increment(amount),
                  'lastUpdated': FieldValue.serverTimestamp(),
                });
                
                await batch.commit();
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  void _showLogsDialog(BuildContext context, String charId, String charName) {
    showDialog(
      context: context,
      builder: (context) => _LogsDialog(charId: charId, charName: charName, firestore: _firestore),
    );
  }

  void _showDeleteConfirmation(BuildContext context, String charId, String charName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить персонажа?'),
        content: Text('Это удалит персонажа "$charName" и всю его историю прибыли. Действие необратимо.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _firestore.collection('characters').doc(charId).delete();
              // Optional: delete logs as well? For simplicity, we keep the top-level logs but they won't show up.
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }
}

class _CharacterCard extends StatelessWidget {
  final String docId;
  final String name;
  final double totalProfit;
  final VoidCallback onAddProfit;
  final VoidCallback onShowLogs;
  final VoidCallback onDelete;

  const _CharacterCard({
    required this.docId,
    required this.name,
    required this.totalProfit,
    required this.onAddProfit,
    required this.onShowLogs,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final goldFormat = NumberFormat("#,##0", "en_US");
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF4A4A4A), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF1E3A8A),
                  child: Text(name.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text('${goldFormat.format(totalProfit)} ', 
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                          const Text('з', style: TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.history, color: Colors.blueAccent),
                  tooltip: 'История',
                  onPressed: onShowLogs,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  onPressed: onDelete,
                ),
              ],
            ),
            const Divider(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onAddProfit,
                icon: const Icon(Icons.add_chart),
                label: const Text('Добавить прибыль'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4BF7A).withAlpha(30),
                  foregroundColor: const Color(0xFFD4BF7A),
                  side: const BorderSide(color: Color(0xFFD4BF7A)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogsDialog extends StatelessWidget {
  final String charId;
  final String charName;
  final FirebaseFirestore firestore;

  const _LogsDialog({required this.charId, required this.charName, required this.firestore});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

    return AlertDialog(
      title: Text('Логи прибыли: $charName'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: StreamBuilder<QuerySnapshot>(
          stream: firestore
              .collection('profit_logs')
              .where('characterId', isEqualTo: charId)
              .orderBy('timestamp', descending: true)
              .limit(50)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final logs = snapshot.data?.docs ?? [];
            if (logs.isEmpty) {
              return const Center(child: Text('Логов пока нет'));
            }

            return ListView.separated(
              itemCount: logs.length,
              separatorBuilder: (context, index) => const Divider(color: Colors.white12),
              itemBuilder: (context, index) {
                final logData = logs[index].data() as Map<String, dynamic>;
                final amount = (logData['amount'] ?? 0).toDouble();
                final who = logData['who'] ?? 'Аноним';
                final note = logData['note'] ?? '';
                final ts = logData['timestamp'] as Timestamp?;
                final dateStr = ts != null ? dateFormat.format(ts.toDate()) : '---';

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('+$amount з', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                          Text(dateStr, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Внес: $who', style: const TextStyle(fontSize: 12, color: Color(0xFFD4BF7A))),
                      if (note.isNotEmpty)
                        Text(note, style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.white70)),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть')),
      ],
    );
  }
}
