// Spec 2 W3a (§4.10, C-6, S-7): the one Supabase client every Dating
// repository uses. Today it is the app's own client; W4b replaces this
// provider's body with the Dating-scoped client that sends the trusted-device
// header. No repository changes then.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final datingSupabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);
