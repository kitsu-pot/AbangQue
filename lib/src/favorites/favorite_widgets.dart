import 'package:flutter/material.dart';

import '../domain/passenger_route.dart';
import '../presentation/widgets/glass.dart';
import '../theme.dart';
import 'favorite_controller.dart';

class FavoriteHeart extends StatelessWidget {
  const FavoriteHeart({
    super.key,
    required this.controller,
    required this.route,
    required this.onTap,
  });
  final FavoriteController controller;
  final PassengerRoute route;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final pending = controller.pending.contains(route.id) || controller.loading;
    final saved = controller.contains(route.id);
    return IconButton.filledTonal(
      key: const ValueKey('route-favorite'),
      tooltip: saved ? 'Remove favorite route' : 'Save favorite route',
      onPressed:
          pending ||
              (controller.signedIn &&
                  (!controller.enabled || !controller.loaded))
          ? null
          : onTap,
      icon: pending
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: 'Updating favorites',
              ),
            )
          : Icon(
              saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            ),
    );
  }
}

class FavoriteSection extends StatelessWidget {
  const FavoriteSection({
    super.key,
    required this.controller,
    required this.onSignIn,
    required this.onOpen,
    required this.onRemove,
    this.opening = false,
  });
  final FavoriteController controller;
  final VoidCallback onSignIn;
  final ValueChanged<PassengerRoute> onOpen, onRemove;
  final bool opening;
  @override
  Widget build(BuildContext context) => GlassPanel(
    key: const ValueKey('favorite-section'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.favorite_rounded,
              color: JeepLinkColors.green,
              size: 20,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Favorite Routes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            if (controller.signedIn && controller.enabled)
              IconButton(
                tooltip: 'Refresh favorites',
                onPressed: controller.loading || controller.pending.isNotEmpty
                    ? null
                    : controller.refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (!controller.signedIn) ...[
          const Text(
            'Keep your frequent journeys close. An account is needed to save routes.',
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('guest-favorites'),
            onPressed: onSignIn,
            child: const Text('Access Favorite Routes'),
          ),
        ] else if (!controller.enabled)
          const Text(
            'Favorites are available in API mode. DEMO routes cannot be saved.',
          )
        else ...[
          if (controller.loading || opening)
            const LinearProgressIndicator(semanticsLabel: 'Loading favorites'),
          if (controller.error != null) ...[
            Text(
              controller.error!,
              style: const TextStyle(color: JeepLinkColors.green),
            ),
            TextButton(
              onPressed: controller.loading ? null : controller.refresh,
              child: const Text('Retry favorites'),
            ),
          ],
          if (controller.loaded && controller.items.isEmpty)
            const Text(
              'No favorite routes yet. Choose a registered route and tap its heart to save it.',
            ),
          for (final favorite in controller.items)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: ValueKey('open-favorite-${favorite.route.id}'),
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 8,
                        ),
                      ),
                      onPressed:
                          favorite.available && !opening && !controller.loading
                          ? () => onOpen(favorite.route)
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${favorite.route.origin.label} → ${favorite.route.destination.label}',
                          ),
                          if (!favorite.available)
                            const Text(
                              'Route unavailable',
                              style: TextStyle(
                                color: JeepLinkColors.muted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('remove-favorite-${favorite.route.id}'),
                    tooltip:
                        'Remove ${favorite.route.origin.label} to ${favorite.route.destination.label} from favorites',
                    onPressed:
                        controller.loading ||
                            controller.pending.contains(favorite.route.id)
                        ? null
                        : () => onRemove(favorite.route),
                    icon: controller.pending.contains(favorite.route.id)
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.favorite_rounded,
                            color: JeepLinkColors.green,
                          ),
                  ),
                ],
              ),
            ),
        ],
      ],
    ),
  );
}

enum FavoriteSignIn { login, register }

Future<FavoriteSignIn?> showFavoriteSignIn(BuildContext context) =>
    showModalBottomSheet<FavoriteSignIn>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: GlassPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.favorite_border_rounded,
                color: JeepLinkColors.green,
                size: 32,
              ),
              const SizedBox(height: 16),
              Text(
                'Your journeys, saved',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Log in or create an account to save your favorite routes and access them anytime.',
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(context, FavoriteSignIn.login),
                child: const Text('Log In'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () =>
                    Navigator.pop(context, FavoriteSignIn.register),
                child: const Text('Create Account'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Not Now'),
              ),
            ],
          ),
        ),
      ),
    );
