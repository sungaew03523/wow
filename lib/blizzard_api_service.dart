import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import './wow_config.dart';
import './models/auction_item.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import './models/wow_recipe.dart';

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

  Future<void> downloadMidnightRecipesToFirestore() async {
    final token = await _getAccessToken();
    // Основные профессии: Алхимия, Кузнечное дело, Наложение чар, Инженерное дело,
    // Начертание, Ювелирное дело, Кожевничество, Портняжное дело, Кулинария.
    final List<int> professionIds = [
      171,
      164,
      333,
      202,
      773,
      755,
      165,
      197,
      185
    ];
    final List<WowRecipe> allRecipes = [];

    for (var profId in professionIds) {
      try {
        final profUri = Uri.https(
          '${WowApiConfig.region}.api.blizzard.com',
          '/data/wow/profession/$profId',
          {
            'namespace': WowApiConfig.staticNamespace,
            'locale': WowApiConfig.locale
          },
        );
        var profResponse = await _client.get(_addCacheBust(profUri),
            headers: {'Authorization': 'Bearer $token'});
        if (profResponse.statusCode != 200) continue;

        var profData = jsonDecode(profResponse.body);
        var profName = profData['name'] as String? ?? 'Unknown';
        var skillTiers = profData['skill_tiers'] as List<dynamic>? ?? [];

        // Поиск тира с префиксом Midnight
        var midnightTier = skillTiers.firstWhere(
          (t) => (t['name'] as String? ?? '').contains('Midnight'),
          orElse: () => null,
        );

        if (midnightTier == null) continue;
        int tierId = midnightTier['id'];

        final tierUri = Uri.https(
          '${WowApiConfig.region}.api.blizzard.com',
          '/data/wow/profession/$profId/skill-tier/$tierId',
          {
            'namespace': WowApiConfig.staticNamespace,
            'locale': WowApiConfig.locale
          },
        );
        var tierResponse = await _client.get(_addCacheBust(tierUri),
            headers: {'Authorization': 'Bearer $token'});
        if (tierResponse.statusCode != 200) continue;

        var tierData = jsonDecode(tierResponse.body);
        var categories = tierData['categories'] as List<dynamic>? ?? [];

        List<int> recipeIdsToFetch = [];
        for (var category in categories) {
          var recipes = category['recipes'] as List<dynamic>? ?? [];
          for (var r in recipes) {
            recipeIdsToFetch.add(r['id']);
          }
        }

        // Пакетная выгрузка рецептов по 10 штук одновременно
        const batchSize = 10;
        for (var i = 0; i < recipeIdsToFetch.length; i += batchSize) {
          final end = (i + batchSize < recipeIdsToFetch.length)
              ? i + batchSize
              : recipeIdsToFetch.length;
          final batchIds = recipeIdsToFetch.sublist(i, end);

          final futures =
              batchIds.map((id) => _fetchRecipeDetails(token, id, profName));
          final results = await Future.wait(futures);
          allRecipes.addAll(results.where((r) => r != null).cast<WowRecipe>());
        }
      } catch (e, s) {
        developer.log('Ошибка получения рецептов для профессии $profId',
            error: e, stackTrace: s);
      }
    }

    // Сохранение в Firestore пакетами по 500 (лимит Cloud Firestore WriteBatch)
    final collection = _firestore.collection('recipes');
    var batch = _firestore.batch();
    int count = 0;

    for (var recipe in allRecipes) {
      batch.set(collection.doc(recipe.id.toString()), recipe.toFirestore());
      count++;
      if (count % 500 == 0) {
        await batch.commit();
        batch = _firestore.batch();
      }
    }
    if (count % 500 != 0) {
      await batch.commit();
    }

    developer.log(
        'Все ${allRecipes.length} рецептов Midnight успешно сохранены в Firestore.');
  }

  Future<WowRecipe?> _fetchRecipeDetails(
      String token, int recipeId, String professionName) async {
    try {
      final recipeUri = Uri.https('${WowApiConfig.region}.api.blizzard.com',
          '/data/wow/recipe/$recipeId', {
        'namespace': WowApiConfig.staticNamespace,
        'locale': WowApiConfig.locale
      });
      final mediaUri = Uri.https('${WowApiConfig.region}.api.blizzard.com',
          '/data/wow/media/recipe/$recipeId', {
        'namespace': WowApiConfig.staticNamespace,
        'locale': WowApiConfig.locale
      });

      final responses = await Future.wait([
        _client.get(_addCacheBust(recipeUri),
            headers: {'Authorization': 'Bearer $token'}),
        _client.get(_addCacheBust(mediaUri),
            headers: {'Authorization': 'Bearer $token'}),
      ]);

      if (responses[0].statusCode == 200) {
        final data = jsonDecode(responses[0].body);

        final mediaData = responses[1].statusCode == 200
            ? jsonDecode(responses[1].body)
            : null;
        final assets = mediaData?['assets'] as List?;
        final iconAsset =
            assets?.firstWhere((e) => e['key'] == 'icon', orElse: () => null);

        final name = data['name'] as String? ?? 'Unknown Recipe';
        final craftedItem = data['crafted_item'];
        final craftedItemId =
            craftedItem != null ? craftedItem['id'] as int? : null;
        final craftedQuantity = data['crafted_quantity']?['value'] as int?;

        final reagentsList = data['reagents'] as List<dynamic>? ?? [];
        final List<RecipeReagent> parsedReagents = [];

        for (var r in reagentsList) {
          final reagentItem = r['reagent'];
          if (reagentItem != null) {
            parsedReagents.add(RecipeReagent(
              itemId: reagentItem['id'],
              name: reagentItem['name'] ?? 'Unknown Reagent',
              quantity: r['quantity'] as int? ?? 1,
            ));
          }
        }

        // В Dragonflight / TWW / Midnight API Blizzard скрывает базовые реагенты, имеющие качество (ранги 1-2-3).
        // Это известный баг API, на который жалуются многие разработчики.
        // Тем не менее, API отдает опциональные слоты крафта (modified_crafting_slots), такие как отделочные реагенты, спарк и т.д.
        // Добавим их в список реагентов для отображения.
        final modifiedSlots =
            data['modified_crafting_slots'] as List<dynamic>? ?? [];
        for (var slot in modifiedSlots) {
          final slotType = slot['slot_type'];
          if (slotType != null) {
            parsedReagents.add(RecipeReagent(
              itemId: slotType[
                  'id'], // Используем ID типа слота (это не item ID, но нужно для уникальности)
              name: slotType['name'] ?? 'Опциональный реагент',
              quantity: 1,
            ));
          }
        }

        return WowRecipe(
          id: recipeId,
          name: name,
          iconUrl: iconAsset?['value'] as String?,
          craftedItemId: craftedItemId,
          craftedQuantity: craftedQuantity,
          reagents: parsedReagents,
          professionName: professionName,
        );
      }
    } catch (e, s) {
      developer.log('Ошибка при получении деталей рецепта $recipeId',
          error: e, stackTrace: s);
    }
    return null;
  }
}
