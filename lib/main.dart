import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/screens.dart';
import 'providers/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Enable edge-to-edge mode
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  runApp(const ProviderScope(child: RomgiApp()));
}

class RomgiApp extends ConsumerWidget {
  const RomgiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'romgi',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          scrolledUnderElevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          scrolledUnderElevation: 0,
        ),
      ),
      themeMode: settings.flutterThemeMode,
      home: const WithForegroundTask(child: MainNavigation()),
    );
  }
}

class MainNavigation extends ConsumerStatefulWidget {
  const MainNavigation({super.key});

  @override
  ConsumerState<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends ConsumerState<MainNavigation> {
  final _screens = const [
    BrowseScreen(),
    DownloadsScreen(),
    LibraryScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Trigger library file verification on startup
      ref.read(libraryProvider.notifier).verifyFiles();

      // Set up notification tap handler
      final notifications = ref.read(notificationServiceProvider);
      notifications.setOnTapCallback(_onNotificationTap);
    });
  }

  void _onNotificationTap(String? payload) {
    if (payload == null) return;

    switch (payload) {
      case 'downloads':
        ref.read(navigationTabProvider.notifier).state = NavTab.downloads;
        break;
      case 'library':
        ref.read(navigationTabProvider.notifier).state = NavTab.library;
        break;
    }
  }

  void _onTabSelected(int index) {
    final previousIndex = ref.read(navigationTabProvider);
    ref.read(navigationTabProvider.notifier).state = index;

    // Refresh library when navigating to Library tab
    if (index == NavTab.library && previousIndex != NavTab.library) {
      ref.read(libraryProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(navigationTabProvider);
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final isWideScreen = MediaQuery.of(context).size.width > 600;

    // Use NavigationRail for landscape/wide screens (better for handhelds)
    if (isLandscape || isWideScreen) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: currentIndex,
              onDestinationSelected: _onTabSelected,
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.search),
                  selectedIcon: Icon(Icons.search),
                  label: Text('Browse'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.download_outlined),
                  selectedIcon: Icon(Icons.download),
                  label: Text('Downloads'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.library_books_outlined),
                  selectedIcon: Icon(Icons.library_books),
                  label: Text('Library'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: Text('Settings'),
                ),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(
              child: IndexedStack(
                index: currentIndex,
                children: _screens,
              ),
            ),
          ],
        ),
      );
    }

    // Use bottom NavigationBar for portrait mode
    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: _onTabSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search),
            selectedIcon: Icon(Icons.search),
            label: 'Browse',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: 'Downloads',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
