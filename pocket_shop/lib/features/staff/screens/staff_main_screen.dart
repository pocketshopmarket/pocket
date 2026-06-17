import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class StaffMainScreen extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const StaffMainScreen({super.key, required this.navigationShell});

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _goBranch,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            selectedIcon: Icon(Icons.payments_rounded),
            label: 'Payouts',
          ),
          NavigationDestination(
            icon: Icon(Icons.verified_user_outlined),
            selectedIcon: Icon(Icons.verified_user_rounded),
            label: 'Verify',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_return_outlined),
            selectedIcon: Icon(Icons.assignment_return_rounded),
            label: 'Refunds',
          ),
        ],
      ),
    );
  }
}
