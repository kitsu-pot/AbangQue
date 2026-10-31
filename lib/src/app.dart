import 'config/data_config.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'config/map_config.dart';
import 'domain/jeepney.dart';
import 'domain/jeepney_repository.dart';
import 'presentation/jeepney_controller.dart';
import 'presentation/screens/fleet_screen.dart';
import 'presentation/screens/guide_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/widgets/common.dart';
import 'presentation/widgets/glass.dart';
import 'presentation/widgets/jeepney_details.dart';
import 'presentation/widgets/jeepney_map.dart';
import 'theme.dart';

/// Composition root. Owns the supplied repository for this app's lifetime.
class JeepLinkApp extends StatefulWidget {
  const JeepLinkApp({
    super.key,
    required this.repository,
    this.mapConfig = const MapConfig(),
    this.tileProviderFactory,
    this.apiMode = false,
  });
  final JeepneyRepository repository;
  final bool apiMode;
  final MapConfig mapConfig;
  final TileProviderFactory? tileProviderFactory;

  @override
  State<JeepLinkApp> createState() => _JeepLinkAppState();
}

class _JeepLinkAppState extends State<JeepLinkApp> {
  late final _controller = JeepneyController(
    widget.repository,
    apiMode: widget.apiMode,
  );

  @override
  void dispose() {
    _controller.dispose();
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
      home: _PassengerShell(
        controller: _controller,
        mapConfig: widget.mapConfig,
        tileProviderFactory: widget.tileProviderFactory,
      ),
    ),
  );
}

class _PassengerShell extends StatefulWidget {
  const _PassengerShell({
    required this.controller,
    required this.mapConfig,
    this.tileProviderFactory,
  });
  final JeepneyController controller;
  final MapConfig mapConfig;
  final TileProviderFactory? tileProviderFactory;

  @override
  State<_PassengerShell> createState() => _PassengerShellState();
}

class _PassengerShellState extends State<_PassengerShell> {
  int _tab = 0;
  Jeepney? _focus;
  int _mapSelection = 0;
  final _scrollController = ScrollController();

  void _selectTab(int tab) {
    setState(() {
      _tab = tab;
      _focus = null;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _showDetails(Jeepney jeepney) =>
      showJeepneyDetails(context, jeepney, (selected) {
        widget.controller.setAvailableOnly(false);
        widget.controller.setQuery('');
        setState(() {
          _tab = 1;
          _focus = selected;
          _mapSelection++;
        });
        if (_scrollController.hasClients) _scrollController.jumpTo(0);
      }, widget.controller);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => GlassBackdrop(
      child: Scaffold(
        appBar: AppBar(
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
            IconButton(
              tooltip: modeText(context, 'Refresh demo', 'Refresh API'),
              onPressed: widget.controller.refreshing
                  ? null
                  : widget.controller.refresh,
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
        body: SafeArea(
          top: false,
          bottom: false,
          child: RefreshIndicator(
            onRefresh: widget.controller.refresh,
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
                      if (widget.controller.error != null) ...[
                        EmptyState(
                          title: 'Unable to update the fleet',
                          message: widget.controller.error!,
                          action: FilledButton(
                            onPressed: widget.controller.refresh,
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
                        )
                      else
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
      controller: widget.controller,
      onMap: () => _selectTab(1),
      onJeepneys: () => _selectTab(2),
      onSelect: _showDetails,
      mapConfig: widget.mapConfig,
      tileProviderFactory: widget.tileProviderFactory,
    ),
    1 || 2 => FleetScreen(
      key: ValueKey('fleet-$_tab-$_mapSelection'),
      controller: widget.controller,
      onSelect: _showDetails,
      showMap: _tab == 1,
      focus: _focus,
      mapConfig: widget.mapConfig,
      tileProviderFactory: widget.tileProviderFactory,
    ),
    _ => GuideScreen(onMap: () => _selectTab(1)),
  };
}
