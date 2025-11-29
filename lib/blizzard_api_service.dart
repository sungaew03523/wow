
import 'dart:convert';
import 'package:http/http.dart' as http;
import './wow_config.dart';
import './main.dart'; // Для доступа к AuctionItem

class BlizzardApiService {
  final http.Client _client = http.Client();

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
    const int maxPages = 5; // Ограничение на количество страниц с ID

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
      
      // --- ИСПРАВЛЕННАЯ СТРОКА ---
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
}
