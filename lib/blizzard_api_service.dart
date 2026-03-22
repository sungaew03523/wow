import 'dart:convert';
import 'dart:developer' as developer;
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
    final List<AuctionItem> items =
        await _fetchItemDetails(token, limitedItemIds);
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
          {
            'namespace': WowApiConfig.staticNamespace,
            'locale': WowApiConfig.locale
          },
        );
        final mediaUri = Uri.https(
          '${WowApiConfig.region}.api.blizzard.com',
          '/data/wow/media/item/$id',
          {
            'namespace': WowApiConfig.staticNamespace,
            'locale': WowApiConfig.locale
          },
        );

        final responses = await Future.wait([
          _client.get(_addCacheBust(nameUri),
              headers: {'Authorization': 'Bearer $token'}),
          _client.get(_addCacheBust(mediaUri),
              headers: {'Authorization': 'Bearer $token'}),
        ]);

        if (responses[0].statusCode == 200 && responses[1].statusCode == 200) {
          final nameData = jsonDecode(responses[0].body);
          final mediaData = jsonDecode(responses[1].body);
          final assets = mediaData['assets'] as List?;
          final iconAsset =
              assets?.firstWhere((e) => e['key'] == 'icon', orElse: () => null);

          items.add(AuctionItem(
            id: id,
            name: nameData['name'] as String? ?? 'Без имени',
            iconUrl: iconAsset?['value'] as String?,
          ));
        }
      } catch (e, s) {
        developer.log('Исключение при обработке предмета $id',
            error: e, stackTrace: s);
      }
    }
    return items;
  }

  Future<Map<String, int>> getAuctionQuantities(List<String> itemIds) async {
    if (itemIds.isEmpty) return {};

    final token = await _getAccessToken();
    final Map<String, int> itemQuantities = {for (var id in itemIds) id: 0};

    Uri? nextUri = Uri.https(
        '${WowApiConfig.region}.api.blizzard.com',
        '/data/wow/auctions/commodities',
        {'namespace': WowApiConfig.namespace, 'locale': WowApiConfig.locale});

    while (nextUri != null) {
      final response = await _client.get(_addCacheBust(nextUri),
          headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode != 200) {
        throw Exception('Ошибка commodities: ${response.body}');
      }

      final data = jsonDecode(response.body);
      final auctions =
          (data['auctions'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      for (var auction in auctions) {
        final itemId = auction['item']?['id']?.toString();
        if (itemId != null && itemQuantities.containsKey(itemId)) {
          final quantity = auction['quantity'] as int? ?? 0;
          itemQuantities[itemId] = (itemQuantities[itemId] ?? 0) + quantity;
        }
      }
      final nextLink = data['_links']?['next']?['href'] as String?;
      nextUri = nextLink != null ? Uri.parse(nextLink) : null;
    }

    return itemQuantities;
  }

  Future<void> fetchReagentPrices(Map<String, int> itemsToUpdate) async {
    if (itemsToUpdate.isEmpty) return;

    final token = await _getAccessToken();
    // Оптимизация: используем Set для поиска за O(1)
    final Set<int> favoriteIdsSet =
        itemsToUpdate.keys.map((id) => int.parse(id)).toSet();
    final Map<int, List<Map<String, dynamic>>> auctionsByItem = {};

    Uri? nextUri = Uri.https(
        '${WowApiConfig.region}.api.blizzard.com',
        '/data/wow/auctions/commodities',
        {'namespace': WowApiConfig.namespace, 'locale': WowApiConfig.locale});

    while (nextUri != null) {
      final response = await _client.get(_addCacheBust(nextUri),
          headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode != 200) {
        throw Exception('Ошибка commodities: ${response.body}');
      }

      final data = jsonDecode(response.body);
      final auctions =
          (data['auctions'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      for (var auction in auctions) {
        final itemId = auction['item']?['id'] as int?;
        // Оптимизация: быстрый поиск в Set
        if (itemId != null && favoriteIdsSet.contains(itemId)) {
          auctionsByItem.putIfAbsent(itemId, () => []).add(auction);
        }
      }
      final nextLink = data['_links']?['_next']?['href'] as String? ??
          data['_links']?['next']?['href'] as String?;
      nextUri = nextLink != null ? Uri.parse(nextLink) : null;
    }

    developer.log(
        "Обработка данных аукциона для ${auctionsByItem.length} предметов...");

    final WriteBatch batch = _firestore.batch();
    final now = DateTime.now();
    final timestampKey = DateFormat('yyyy-MM-dd HH').format(now);

    for (var itemId in auctionsByItem.keys) {
      final itemAuctions = auctionsByItem[itemId]!;
      if (itemAuctions.isEmpty) continue;

      int totalItemQuantity = 0;
      for (var auction in itemAuctions) {
        totalItemQuantity += (auction['quantity'] as int?) ?? 0;
      }

      int targetVolume = (totalItemQuantity * 0.10).ceil();
      if (targetVolume < 1) targetVolume = 1;
      if (targetVolume > 3000) targetVolume = 3000;

      itemAuctions.sort(
          (a, b) => (a['unit_price'] as int).compareTo(b['unit_price'] as int));

      double minimalCost = (itemAuctions.first['unit_price'] as int) / 10000.0;
      int accumulatedQuantity = 0;
      double totalCostForWeightedAverage = 0;
      double marketPrice = minimalCost;

      for (var auction in itemAuctions) {
        final quantity = auction['quantity'] as int;
        final unitPrice = (auction['unit_price'] as int) / 10000.0;

        if (accumulatedQuantity < targetVolume) {
          final quantityToConsider =
              (accumulatedQuantity + quantity) > targetVolume
                  ? targetVolume - accumulatedQuantity
                  : quantity;

          totalCostForWeightedAverage += quantityToConsider * unitPrice;
          accumulatedQuantity += quantityToConsider;
          marketPrice = unitPrice;
        } else {
          break;
        }
      }

      double weightedAveragePrice = accumulatedQuantity > 0
          ? totalCostForWeightedAverage / accumulatedQuantity
          : minimalCost;

      // Округление
      weightedAveragePrice = (weightedAveragePrice * 100).round() / 100.0;
      marketPrice = (marketPrice * 100).round() / 100.0;
      minimalCost = (minimalCost * 100).round() / 100.0;

      final docRef = _firestore.collection('favorites').doc(itemId.toString());

      // Оптимизация: используем обновление полей с точечной нотацией для мап.
      // Это работает атомарно без необходимости чтения документа (транзакции).
      batch.update(docRef, {
        'minimalCost': minimalCost,
        'marketPrice': marketPrice,
        'weightedAveragePrice': weightedAveragePrice,
        'averagePriceHistory.$timestampKey': weightedAveragePrice,
        'totalQuantityHistory.$timestampKey': totalItemQuantity,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    developer.log("Все цены успешно обновлены пакетом.");
  }
}
