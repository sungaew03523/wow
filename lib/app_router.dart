import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/auction_house_screen.dart'; // Исправленный импорт
import 'favorites_screen.dart';
import 'farms_screen.dart';

// --- Навигация ---
final GoRouter router = GoRouter(
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) {
        return const AuctionHouseScreen();
      },
    ),
    GoRoute(
      path: '/favorites',
      builder: (BuildContext context, GoRouterState state) {
        return const FavoritesScreen();
      },
    ),
    GoRoute(
      path: '/farms',
      builder: (BuildContext context, GoRouterState state) {
        return const FarmsScreen();
      },
    ),
  ],
);
