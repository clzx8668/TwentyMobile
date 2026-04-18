import 'package:pocketcrm/core/di/providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_state.g.dart';

@riverpod
class AuthState extends _$AuthState {
  String _normalizeToken(String raw) => raw.replaceAll(RegExp(r'\s+'), '');

  @override
  Future<bool> build() async {
    print('AuthState: build started');
    final storage = ref.read(storageServiceProvider);
    final token = await storage.read(key: 'api_token');
    final url = await storage.read(key: 'instance_url');
    print('AuthState: read token -> ${token != null}, url -> ${url != null}');
    return (token != null && _normalizeToken(token).isNotEmpty) && url != null;
  }

  Future<void> login(String token, {bool isDemo = false}) async {
    final storage = ref.read(storageServiceProvider);
    final normalizedToken = _normalizeToken(token);
    await storage.write(key: 'api_token', value: normalizedToken);
    await storage.write(key: 'is_demo_mode', value: isDemo.toString());
    state = const AsyncValue.data(true);
  }

  Future<void> logout() async {
    final storage = ref.read(storageServiceProvider);
    await storage.delete(key: 'api_token');
    await storage.delete(key: 'is_demo_mode');
    state = const AsyncValue.data(false);
  }
}
