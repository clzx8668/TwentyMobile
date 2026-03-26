import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/notifications/notification_service.dart';

class NotificationPermissionScreen extends StatelessWidget {
  const NotificationPermissionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.notifications_active, size: 80, color: Colors.blue),
              const SizedBox(height: 24),
              const Text(
                'Stay updated',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Receive reminders for your upcoming tasks',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              FilledButton(
                onPressed: () async {
                  await NotificationService().requestPermission();
                  if (context.mounted) {
                    context.go('/home');
                  }
                },
                child: const Text('Enable notifications'),
              ),
              TextButton(
                onPressed: () => context.go('/home'),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
