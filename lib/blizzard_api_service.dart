import 'dart:convert';
import 'package:http/http.dart' as http;
import './wow_config.dart';
import './models/auction_item.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['access_token'];
    }
    throw Exception('Ошибка получения токена: ${response.statusCode}');
  }

  Uri _addCacheBust(Uri uri) {
    final params = Map<String, dynamic>.from(uri.queryParameters);
    params['_'] = DateTime.now().millisecondsSinceEpoch.toString();
    return uri.replace(queryParameters: params);
  }

  Future<int> fetchWowTokenPrice() async {
    final token = await _getAccessToken();
    final uri = Uri.https(
      '${WowApiConfig.region}.api.blizzard.com',
      '/data/wow/token/index',
      {
        'namespace': WowApiConfig.namespace,
        'locale': WowApiConfig.locale,
      },
    );

    final response = await _client.get(
      _addCacheBust(uri),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final priceInCopper = data['price'] as int;
      return priceInCopper ~/ 10000;
    } else {
      throw Exception(
          'Ошибка загрузки цены жетона: ${response.statusCode} ${response.body}');
    }
  }

  Future<List<AuctionItem>> fetchItemsFromBlizzard() async {
    final token = await _getAccessToken();
    final Set<int> itemIds = await _fetchCommodityIds(token);
    final limitedItemIds = itemIds.take(100).toSet();
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
      final response = await _client.get(
        _addCacheBust(nextUri),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) {
        throw Exception('Ошибка commodities: ${response.body}');
      }

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
    return listID;
  }

  Future<List<AuctionItem>> _fetchItemDetails(
    String token,
    Set<int> itemIds,
  ) async {
    List<AuctionItem> items = [];
    for (final id in itemIds) {
      try {
        final nameUri = Uri.https(
          '${WowApiConfig.region}.api.blizzard.com',
          '/data/wow/item/$id',
          {'namespace': WowApiConfig.staticNamespace, 'locale': WowApiConfig.locale},
        );
        final mediaUri = Uri.https(
          '${WowApiConfig.region}.api.blizzard.com',
          '/data/wow/media/item/$id',
          {'namespace': WowApiConfig.staticNamespace, 'locale': WowApiConfig.locale},
        );

        final responses = await Future.wait([
          _client.get(_addCacheBust(nameUri), headers: {'Authorization': 'Bearer $token'}),
          _client.get(_addCacheBust(mediaUri), headers: {'Authorization': 'Bearer $token'}),
        ]);

        if (responses[0].statusCode == 200 && responses[1].statusCode == 200) {
          final nameData = jsonDecode(responses[0].body);
          final mediaData = jsonDecode(responses[1].body);
          final assets = mediaData['assets'] as List?;
          final iconAsset = assets?.firstWhere((e) => e['key'] == 'icon', orElse: () => null);

          items.add(AuctionItem(
            id: id,
            name: nameData['name'] as String? ?? 'Без имени',
            iconUrl: iconAsset?['value'] as String?,
          ));
        }
      } catch (e) {
        print('Исключение при обработке предмета $id: $e');
      }
    }
    return items;
  }

  Future<void> fetchReagentPrices(Map<String, int> itemsToUpdate) async {
    if (itemsToUpdate.isEmpty) return;

    final token = await _getAccessToken();
    final favoriteIds = itemsToUpdate.keys.toList();
    final Map<int, List<Map<String, dynamic>>> auctionsByItem = {};

    Uri? nextUri = Uri.https(
        '${WowApiConfig.region}.api.blizzard.com',
        '/data/wow/auctions/commodities',
        {'namespace': WowApiConfig.namespace, 'locale': WowApiConfig.locale});

    while (nextUri != null) {
      final response = await _client.get(_addCacheBust(nextUri), headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode != 200) throw Exception('Ошибка commodities: ${response.body}');
      
      final data = jsonDecode(response.body);
      final auctions = (data['auctions'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      for (var auction in auctions) {
        final itemId = auction['item']?['id'] as int?;
        if (itemId != null && favoriteIds.contains(itemId.toString())) {
          auctionsByItem.putIfAbsent(itemId, () => []).add(auction);
        }
      }
      final nextLink = data['_links']?['next']?['href'] as String?;
      nextUri = nextLink != null ? Uri.parse(nextLink) : null;
    }

    print("--- Начинаем новый расчет цен ---");

    for (var itemIdStr in favoriteIds) {
      final itemId = int.parse(itemIdStr);
      final analysisVolume = itemsToUpdate[itemIdStr] ?? 1000;
      final itemAuctions = auctionsByItem[itemId];

      print("\n--- Обработка предмета ID: $itemId (Объем: $analysisVolume) ---");

      if (itemAuctions == null || itemAuctions.isEmpty) {
        print('Нет аукционов для предмета $itemId, пропуск.');
        continue;
      }
      
      itemAuctions.sort((a, b) => (a['unit_price'] as int).compareTo(b['unit_price'] as int));

      double minimalCost = (itemAuctions.first['unit_price'] as int) / 10000.0;
      print("Минимальная цена (самый дешевый лот): $minimalCost");

      int accumulatedQuantity = 0;
      double totalCostForWeightedAverage = 0;
      double marketPrice = minimalCost;

      print("Начинаем итерацию по отсортированным лотам:");
      int lotCounter = 0;
      for (var auction in itemAuctions) {
        lotCounter++;
        final quantity = auction['quantity'] as int;
        final unitPrice = (auction['unit_price'] as int) / 10000.0;

        if (accumulatedQuantity < analysisVolume) {
          final quantityToConsider = (accumulatedQuantity + quantity) > analysisVolume
              ? analysisVolume - accumulatedQuantity
              : quantity;

          print("  Лот $lotCounter: Цена: $unitPrice, Кол-во: $quantity. Учитываем: $quantityToConsider");
          
          totalCostForWeightedAverage += quantityToConsider * unitPrice;
          accumulatedQuantity += quantityToConsider;
          marketPrice = unitPrice;

          print("    -> Накоплено кол-во: $accumulatedQuantity, Общая стоимость для среднего: ${totalCostForWeightedAverage.toStringAsFixed(2)}, Цена стены: $marketPrice");
        } else {
           print("  Лот $lotCounter: Цена: $unitPrice, Кол-во: $quantity. Пропускаем (объем $analysisVolume достигнут).");
           break;
        }
      }

      double weightedAveragePrice = accumulatedQuantity > 0
          ? totalCostForWeightedAverage / accumulatedQuantity
          : minimalCost;

      print("--- ИТОГ для ID: $itemId ---");
      print("  Цена стены (Market Price): ${marketPrice.toStringAsFixed(2)}");
      print("  Средневзвешенная цена (Weighted Avg): ${weightedAveragePrice.toStringAsFixed(2)}");

      final docRef = _firestore.collection('favorites').doc(itemIdStr);
      await _firestore.runTransaction((transaction) async {
        final docSnapshot = await transaction.get(docRef);
        if (!docSnapshot.exists) return;

        final data = docSnapshot.data() as Map<String, dynamic>;
        final history = (data['averagePriceHistory'] as Map<String, dynamic>?) ?? {};

        final now = DateTime.now();
        final formatter = DateFormat('yyyy-MM-dd HH');
        final timestampKey = formatter.format(now);
        history[timestampKey] = weightedAveragePrice;

        const maxHistoryLength = 24;
        if (history.length > maxHistoryLength) {
          final sortedKeys = history.keys.toList()..sort();
          final keysToRemove = sortedKeys.take(history.length - maxHistoryLength);
          for (final key in keysToRemove) history.remove(key);
        }

        transaction.update(docRef, {
          'minimalCost': minimalCost,
          'marketPrice': marketPrice,
          'weightedAveragePrice': weightedAveragePrice,
          'averagePriceHistory': history,
        });
      });
    }
    print("Цены для ${favoriteIds.length} избранных предметов обновлены.");
  }
}
