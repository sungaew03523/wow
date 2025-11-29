
import 'dart:convert';
import 'package:http/http.dart' as http;
import './wow_config.dart';
import './main.dart'; // Для доступа к AuctionItem
import 'package:cloud_firestore/cloud_firestore.dart';


class ReagentPrice {
  final int itemId;
  final int quantity;
  final double minimalCost;
  final List<double> costList;
  final double averageCost;
  final String pictureRef;
  final String name;

  ReagentPrice({
    required this.itemId,
    required this.quantity,
    required this.minimalCost,
    required this.costList,
    required this.averageCost,
    required this.pictureRef,
    required this.name,
  });
}

class BlizzardApiService {
  final http.Client _client = http.Client();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String> _getAccessToken() async {
    final credentials = '${WowApiConfig.clientId}:${WowApiConfig.clientSecret}';
    final encodedCredentials = base64.encode(utf8.encode(credentials));
    final response = await _client.post(
      Uri.parse('https://oauth.battle.net/token'),
      headers: {'Authorization': 'Basic $encodedCredentials'},
      body: {'grant_type': 'client_credentials'},
    );
    if (response.statusCode == 200) return jsonDecode(response.body)['access_token'];
    throw Exception('Ошибка получения токена: ${response.statusCode}');
  }

  Future<List<AuctionItem>> fetchItemsFromBlizzard() async {
    final token = await _getAccessToken();
    final Set<int> itemIds = await _fetchCommodityIds(token);
    
    final limitedItemIds = itemIds.take(100).toSet();
    print('Будет загружено ${limitedItemIds.length} предметов (лимит 100).');

    final List<AuctionItem> items = await _fetchItemDetails(token, limitedItemIds);
    return items;
  }

  Future<Set<int>> _fetchCommodityIds(String token) async {
    Uri? nextUri = Uri.https(
      '${WowApiConfig.region}.api.blizzard.com',
      '/data/wow/auctions/commodities',
      {'namespace': WowApiConfig.namespace, 'locale': WowApiConfig.locale},
    );
    final Set<int> listID = {};
    int pageCount = 0;
    const int maxPages = 5; 

    while (nextUri != null && pageCount < maxPages) {
      pageCount++;
      final response = await _client.get(nextUri, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode != 200) throw Exception('Ошибка commodities: ${response.body}');
      
      final data = jsonDecode(response.body);
      final commoditiesRaw = data['auctions'] as List?;
      if (commoditiesRaw == null) break;

      for (final commodity in commoditiesRaw) {
        final item = commodity['item'] as Map<String, dynamic>?;
        if (item != null) listID.add(item['id'] as int);
      }
      
      final nextLink = data['_links']?['next']?['href'] as String?;
      nextUri = nextLink != null ? Uri.parse(nextLink) : null;
    }
    print('Найдено ${listID.length} уникальных ID на $pageCount страницах.');
    return listID;
  }

  Future<List<AuctionItem>> _fetchItemDetails(String token, Set<int> itemIds) async {
    List<AuctionItem> items = [];

    for (final id in itemIds) {
      try {
        final nameUri = Uri.https('${WowApiConfig.region}.api.blizzard.com', '/data/wow/item/$id', {'namespace': WowApiConfig.staticNamespace, 'locale': WowApiConfig.locale});
        final mediaUri = Uri.https('${WowApiConfig.region}.api.blizzard.com', '/data/wow/media/item/$id', {'namespace': WowApiConfig.staticNamespace, 'locale': WowApiConfig.locale});

        final responses = await Future.wait([
          _client.get(nameUri, headers: {'Authorization': 'Bearer $token'}),
          _client.get(mediaUri, headers: {'Authorization': 'Bearer $token'}),
        ]);

        final nameResponse = responses[0];
        final mediaResponse = responses[1];

        if (nameResponse.statusCode == 200 && mediaResponse.statusCode == 200) {
          final nameData = jsonDecode(nameResponse.body);
          final mediaData = jsonDecode(mediaResponse.body);

          final assets = mediaData['assets'] as List?;
          final iconAsset = assets?.firstWhere((e) => e['key'] == 'icon', orElse: () => null);
          
          items.add(AuctionItem(
            id: id,
            name: nameData['name'] as String? ?? 'Без имени',
            iconUrl: iconAsset?['value'] as String?,
          ));
        } else {
          print('Ошибка для ID $id: Name Status=${nameResponse.statusCode}, Media Status=${mediaResponse.statusCode}');
        }
      } catch (e) {
        print('Исключение при обработке предмета $id: $e');
      }
    }
    print('Загружены детали для ${items.length} предметов.');
    return items;
  }

  Future<void> fetchReagentPrices(
      int countForAverage, List<String> ids) async {
    if (ids.isEmpty) {
      print("Список ID для обновления пуст.");
      return;
    }
    
    final token = await _getAccessToken();

    Uri? nextUri = Uri.https(
      '${WowApiConfig.region}.api.blizzard.com',
      '/data/wow/auctions/commodities',
      {
        'namespace': WowApiConfig.namespace,
        'locale': WowApiConfig.locale,
      },
    );

    final Map<int, ReagentPrice> aggregated = {};

    while (nextUri != null) {
      final response = await _client.get(
        nextUri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception(
            'Ошибка загрузки commodities: ${response.statusCode} ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final commoditiesRaw = data['auctions'];
      final commodities = (commoditiesRaw as List).cast<Map<String, dynamic>>();

      for (final commodity in commodities) {
        final item = commodity['item'] as Map<String, dynamic>?;
        if (item == null) continue;

        final itemId = item['id'] as int;
        if (!ids.contains(itemId.toString())) continue;

        final quantity = commodity['quantity'] as int? ?? 0;
        final unitPriceCopper = commodity['unit_price'] as int?;

        if (quantity == 0 || unitPriceCopper == null) continue;

        final totalPriceGold = (unitPriceCopper * quantity) / 10000.0;
        
        double sumFirstX(List<double> costList) {
          double sum;
          if (costList.length < countForAverage) {
            sum = costList.isEmpty ? 0.0 : costList.reduce((a, b) => a + b) / costList.length;
          } else {
             sum = 0.0;
            for (int i = 0; i < countForAverage; i++) {
              sum += costList[i];
            }
            sum /= countForAverage;
          }
          return double.parse(sum.toStringAsFixed(2));
        }

        final existing = aggregated[itemId];
        final currentCost = double.parse((totalPriceGold / quantity).toStringAsFixed(2));

        if (existing == null) {
          final newCostList = [currentCost];
          aggregated[itemId] = ReagentPrice(
              itemId: itemId,
              quantity: quantity,
              minimalCost: currentCost,
              costList: newCostList,
              averageCost: sumFirstX(newCostList),
              pictureRef: '',
              name: '');
        } else {
          final updatedCostList = [...existing.costList, currentCost];
          updatedCostList.sort();

          final newMinimalCost = double.parse((currentCost < existing.minimalCost ? currentCost : existing.minimalCost).toStringAsFixed(2));
          
          aggregated[itemId] = ReagentPrice(
              itemId: itemId,
              quantity: existing.quantity + quantity,
              minimalCost: newMinimalCost,
              costList: updatedCostList,
              averageCost: sumFirstX(updatedCostList),
              pictureRef: '',
              name: '');
        }
      }
      final nextLink = data['_links']?['next']?['href'] as String?;
      nextUri = nextLink != null ? Uri.parse(nextLink) : null;
    }

    // Обновляем данные в Firestore
    final batch = _firestore.batch();
    for (final priceData in aggregated.values) {
      final docRef = _firestore.collection('favorites').doc(priceData.itemId.toString());
      batch.update(docRef, {
        'minimalCost': priceData.minimalCost,
        'averageCost': priceData.averageCost,
      });
    }
    await batch.commit();
    print("Цены для ${aggregated.length} избранных предметов обновлены.");
  }
}
