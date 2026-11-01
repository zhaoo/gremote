import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../darkroom/darkroom_providers.dart';
import 'extensions_controller.dart';

final extensionMutationPendingProvider =
    StateProvider.family<bool, String>((ref, id) => false);

/// Fail closed while durable pending state is being loaded after app restart.
final extensionPendingPresenceProvider = FutureProvider.family<bool, String>(
    (ref, id) async =>
        await SqliteExtensionPendingStore(ref.watch(databaseProvider), id)
            .load() !=
        null);
