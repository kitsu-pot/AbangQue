import 'presentation/widgets/connection_notice.dart';
import 'favorites/favorite_controller.dart';
import 'favorites/favorite_repository.dart';
import 'favorites/favorite_widgets.dart';
import 'config/data_config.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_screens.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'config/map_config.dart';
import 'domain/jeepney.dart';
import 'domain/jeepney_repository.dart';
import 'domain/passenger_route.dart';
import 'presentation/jeepney_controller.dart';
import 'presentation/screens/fleet_screen.dart';
import 'presentation/screens/route_map_screen.dart';
import 'presentation/screens/guide_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/widgets/common.dart';
import 'presentation/widgets/glass.dart';
import 'presentation/widgets/jeepney_details.dart';
import 'presentation/widgets/jeepney_map.dart';
import 'theme.dart';
import 'location/device_location_service.dart';
import 'location/waiting_location_controller.dart';
import 'location/waiting_location_panel.dart';
import 'location/waiting_location_picker.dart';
import 'location/waiting_location.dart';

/// Composition root. Owns the supplied repository for this app's lifetime.
class JeepLinkApp extends StatefulWidget {
  const JeepLinkApp({
    super.key,
    required this.repository,
    this.mapConfig = const MapConfig(),
    this.tileProviderFactory,
    this.apiMode = false,
    this.pollInterval,
    this.authController,
    this.favoriteRepository,
    this.locationService,
    this.routeRepository = const UnconfiguredRouteRepository(),
  });
  final FavoriteRepository? favoriteRepository;
  final DeviceLocationService? locationService;
  final JeepneyRepository repository;
  final AuthController? authController;
  final RouteRepository routeRepository;
  final bool apiMode;
  final Duration? pollInterval;
  final MapConfig mapConfig;
  final TileProviderFactory? tileProviderFactory;

  @override
  State<JeepLinkApp> createState() => _JeepLinkAppState();
}

class _JeepLinkAppState extends State<JeepLinkApp> with WidgetsBindingObserver {
  final _waiting = WaitingLocationController();
  late final _favorites = FavoriteController(
    auth: widget.authController,
    repository: widget.favoriteRepository,
  );
  late final _locationService =
      widget.locationService ?? ForegroundDeviceLocationService();
  String? _accountId;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _accountId = widget.authController?.user?.id;
    widget.authController?.addListener(_accountChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller.setActive(true);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _controller.setActive(false);
    }
  }

  void _accountChanged() {
    final id = widget.authController?.user?.id;
    if (id != _accountId) {
      _accountId = id;
      _waiting.clear();
      _locationService.cancel();
    }
  }

  late final _controller = JeepneyController(
    widget.repository,
    apiMode: widget.apiMode,
    pollInterval: widget.pollInterval,
    routeRepository: widget.routeRepository,
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.authController?.removeListener(_accountChanged);
    _locationService.cancel();
    _waiting.dispose();
    _controller.dispose();
    _favorites.dispose();
    widget.authController?.dispose();
    unawaited(widget.repository.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DataModeScope(
    apiMode: widget.apiMode,
    child: MaterialApp(
      title: widget.apiMode ? 'AbangQue · API' : 'AbangQue · Offline demo',
      debugShowCheckedModeBanner: false,
      theme: JeepLinkColors.theme,
      home: widget.authController == null
          ? _shell()
          : AuthGate(controller: widget.authController!, child: _shell()),
    ),
  );
  Widget _shell() => _PassengerShell(
    controller: _controller,
    favorites: _favorites,
    mapConfig: widget.mapConfig,
    tileProviderFactory: widget.tileProviderFactory,
    authController: widget.authController,
    waiting: _waiting,
    locationService: _locationService,
  );
}

class _PassengerShell extends StatefulWidget {
  const _PassengerShell({
    required this.controller,
    required this.favorites,
    required this.mapConfig,
    required this.waiting,
    required this.locationService,
    this.tileProviderFactory,
    this.authController,
  });
  final AuthController? authController;
  final FavoriteController favorites;
  final WaitingLocationController waiting;
  final DeviceLocationService locationService;
  final JeepneyController controller;
  final MapConfig mapConfig;
  final TileProviderFactory? tileProviderFactory;

  @override
  State<_PassengerShell> createState() => _PassengerShellState();
}

class _PassengerShellState extends State<_PassengerShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.waiting.cancel();
    }
  }

  void _findOnMap() {
    _selectTab(1);
    if (widget.waiting.selected?.source != WaitingLocationSource.manualMap) {
      unawaited(widget.waiting.locate(widget.locationService));
    }
  }

  void _locationOptions() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => AnimatedBuilder(
        animation: widget.waiting,
        builder: (_, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.waiting.failure != null)
                Text(widget.waiting.failure!.message),
              if (widget.waiting.failure?.problem == LocationProblem.denied ||
                  widget.waiting.failure?.problem ==
                      LocationProblem.deniedForever)
                TextButton(
                  onPressed: widget.locationService.openAppSettings,
                  child: const Text('Open app settings'),
                ),
              if (widget.waiting.failure?.problem == LocationProblem.disabled)
                TextButton(
                  onPressed: widget.locationService.openLocationSettings,
                  child: const Text('Open location settings'),
                ),
              _waitingPanel(),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _openingFavorite = false;

  Future<void> _favoriteSignIn() async {
    final choice = await showFavoriteSignIn(context);
    final auth = widget.authController;
    if (!mounted || choice == null || auth == null) return;
    auth.clearError();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AuthScreen(
          controller: auth,
          initialRegister: choice == FavoriteSignIn.register,
          returnToJourney: true,
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(PassengerRoute route) async {
    if (!widget.favorites.signedIn) {
      await _favoriteSignIn();
      return;
    }
    await widget.favorites.toggle(route);
    if (!mounted) return;
    final error =
        widget.favorites.error ??
        (!widget.favorites.signedIn ? widget.authController?.error : null);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _openFavorite(PassengerRoute route) async {
    if (_openingFavorite || !widget.favorites.signedIn) return;
    final account = widget.authController?.user?.id;
    setState(() => _openingFavorite = true);
    final opened = await widget.controller.openFavorite(route.id);
    if (!mounted) return;
    setState(() => _openingFavorite = false);
    if (widget.authController?.user?.id != account) return;
    if (opened) {
      _findOnMap();
    } else {
      unawaited(widget.favorites.refresh());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.routesError ?? 'This route is no longer available. Your favorite can still be removed.',
          ),
        ),
      );
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      widget.controller.refresh(),
      widget.favorites.refresh(),
    ]);
  }

  Widget? _favoriteHeart() {
    final route = widget.controller.selectedRoute;
    if (route == null || route.isDemo) return null;
    return FavoriteHeart(
      controller: widget.favorites,
      route: route,
      onTap: () => _toggleFavorite(route),
    );
  }

  int _tab = 0;
  final _scrollController = ScrollController();

  Future<void> _chooseWaiting({required bool device}) async {
    Navigator.of(context).pop();
    widget.waiting.cancel();
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    final accountId = widget.authController?.user?.id;
    final location = await Navigator.of(context).push<WaitingLocation>(
      MaterialPageRoute(
        builder: (_) => WaitingLocationPicker(
          service: widget.locationService,
          initial: widget.waiting.selected,
          requestDeviceLocation: device,
          mapConfig: widget.mapConfig,
          tileProviderFactory: widget.tileProviderFactory,
        ),
      ),
    );
    if (!mounted ||
        location == null ||
        widget.authController?.user?.id != accountId) {
      return;
    }
    widget.waiting.confirm(location);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Waiting location confirmed for this session.'),
      ),
    );
  }

  Widget _waitingPanel() => WaitingLocationPanel(
    selected: widget.waiting.selected,
    onDevice: () => _chooseWaiting(device: true),
    onMap: () => _chooseWaiting(device: false),
    onClear: () {
      widget.waiting.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting location cleared.')),
      );
    },
    onViewMap: () {
      Navigator.pop(context);
      _selectTab(1);
    },
  );

  void _selectTab(int tab) {
    if (tab != 1) widget.waiting.cancel();
    setState(() {
      _tab = tab;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _showDetails(Jeepney jeepney) =>
      showJeepneyDetails(context, jeepney, (selected) {
        widget.controller.setQuery('');
        widget.controller.selectJeepney(selected);
        setState(() {
          _tab = 1;
        });
        if (_scrollController.hasClients) _scrollController.jumpTo(0);
      }, widget.controller);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.waiting.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      widget.controller,
      widget.waiting,
      widget.favorites,
    ]),
    builder: (context, _) => GlassBackdrop(
      child: Scaffold(
        appBar: _tab == 1
            ? null
            : AppBar(
                toolbarHeight: MediaQuery.textScalerOf(context).scale(1) > 1.5
                    ? 104
                    : 80,
                titleSpacing: 16,
                title: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: JeepLinkColors.green,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.airport_shuttle_rounded,
                        color: JeepLinkColors.lime,
                        size: 27,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AbangQue',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.7,
                            ),
                          ),
                          Text(
                            'MARINDUQUE',
                            style: TextStyle(
                              fontSize: 8,
                              letterSpacing: 1.1,
                              color: JeepLinkColors.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  if (widget.authController != null)
                    IconButton(
                      tooltip: 'Passenger profile',
                      icon: const Icon(Icons.account_circle_outlined),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PassengerProfileScreen(
                            controller: widget.authController!,
                          ),
                        ),
                      ),
                    ),

                  IconButton(
                    tooltip: modeText(context, 'Refresh demo', 'Refresh API'),
                    onPressed: widget.controller.refreshing ? null : _refresh,
                    icon: widget.controller.refreshing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              semanticsLabel: 'Refreshing fleet',
                            ),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
        body: _tab == 1
            ? RouteMapScreen(
                favoriteButton: _favoriteHeart(),
                onRefresh: _refresh,
                controller: widget.controller,
                waiting: widget.waiting,
                onFind: _findOnMap,
                onLocate: () => widget.waiting.locate(widget.locationService),
                onWaitingOptions: _locationOptions,
                onDetails: _showDetails,
                mapConfig: widget.mapConfig,
                tileProviderFactory: widget.tileProviderFactory,
              )
            : SafeArea(
                top: false,
                bottom: false,
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: SingleChildScrollView(
                    key: const ValueKey('page-scroll'),
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1040),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.controller.hasSimulationRoutes) ...[
                              const GlassPanel(
                                child: Text(
                                  'SIMULATED / DEMO GPS TEST · Positions and status are generated by a local test tool. Not real traffic or an operating route.',
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (widget.controller.managesConnectivity) ...[
                              ConnectionNotice(
                                controller: widget.controller,
                                onRetry: _refresh,
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (widget.controller.error != null &&
                                !widget.controller.managesConnectivity) ...[
                              EmptyState(
                                title: 'Unable to update the fleet',
                                message: widget.controller.error!,
                                action: FilledButton(
                                  onPressed: _refresh,
                                  child: const Text('Try again'),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                            if (widget.controller.loading && _tab != 3)
                              const Padding(
                                padding: EdgeInsets.all(80),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    semanticsLabel: 'Loading jeepneys',
                                  ),
                                ),
                              ),
                            SoftEntrance(key: ValueKey(_tab), child: _page()),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: GlassPanel(
            frosted: true,
            radius: 28,
            padding: EdgeInsets.zero,
            child: NavigationBar(
              height: 72,
              elevation: 0,
              selectedIndex: _tab,
              onDestinationSelected: _selectTab,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map_rounded),
                  label: 'Map',
                ),
                NavigationDestination(
                  icon: Icon(Icons.airport_shuttle_outlined),
                  selectedIcon: Icon(Icons.airport_shuttle_rounded),
                  label: 'Jeepneys',
                ),
                NavigationDestination(
                  icon: Icon(Icons.help_outline_rounded),
                  selectedIcon: Icon(Icons.help_rounded),
                  label: 'Guide',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _page() => switch (_tab) {
    0 => HomeScreen(
      favorites: FavoriteSection(
        controller: widget.favorites,
        onSignIn: _favoriteSignIn,
        onOpen: _openFavorite,
        onRemove: _toggleFavorite,
        opening: _openingFavorite,
      ),
      controller: widget.controller,
      onFind: _findOnMap,
      waitingPanel: TextButton(
        onPressed: _locationOptions,
        child: const Text('Waiting location options'),
      ),
    ),
    2 => FleetScreen(
      key: const ValueKey('fleet-list'),
      controller: widget.controller,
      onSelect: _showDetails,
      onFind: _findOnMap,
      waitingPanel: TextButton(
        onPressed: _locationOptions,
        child: const Text('Waiting location options'),
      ),
    ),
    _ => GuideScreen(onMap: () => _selectTab(1)),
  };
}
