import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/home_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/profit_screen.dart';
import 'screens/farms2_screen.dart';

// --- Навигация ---
final GoRouter router = GoRouter(
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) {
        return const HomeScreen();
      },
    ),
    GoRoute(
      path: '/favorites',
      builder: (BuildContext context, GoRouterState state) {
        return const FavoritesScreen();
      },
    ),
    GoRoute(
      path: '/profit',
      builder: (BuildContext context, GoRouterState state) {
        return const ProfitScreen();
      },
    ),
    GoRoute(
      path: '/farms2',
      builder: (BuildContext context, GoRouterState state) {
        return const Farms2Screen();
      },
    ),
  ],
);
