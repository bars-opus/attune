import 'package:attune/core/utils/location/models/parsed_address.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:debounce_throttle/debounce_throttle.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/utils/location/location_search_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationSearchScreen extends ConsumerStatefulWidget {
  final LocationSearchMode mode;

  const LocationSearchScreen({
    super.key,
    this.mode = LocationSearchMode.city,
  });

  @override
  ConsumerState<LocationSearchScreen> createState() =>
      _LocationSearchScreenState();
}

class _LocationSearchScreenState extends ConsumerState<LocationSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoadingSuggestions = false;
  bool _hasActiveQuery = false; // true when user has typed ≥3 chars
  List<dynamic> _suggestions = [];
  final _debouncer = Debouncer(
    const Duration(milliseconds: 500),
    initialValue: '',
    checkEquality: true,
  );

  List<String> _recentSearches = [];

  bool get _isAddressMode => widget.mode == LocationSearchMode.address;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();

    _debouncer.values.listen((value) {
      if (value.isNotEmpty && value.length > 2) {
        _getSearchSuggestions(value);
      } else {
        setState(() {
          _suggestions = [];
          _hasActiveQuery = false;
        });
      }
    });

    _searchController.addListener(() {
      final text = _searchController.text;
      _debouncer.setValue(text);
      // Update active query flag immediately so UI responds before debounce fires
      if (text.length > 2 != _hasActiveQuery) {
        setState(() => _hasActiveQuery = text.length > 2);
      }
    });
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final searches = prefs.getStringList('recent_location_searches') ?? [];
    if (mounted) {
      setState(() => _recentSearches = searches);
    }
  }

  Future<void> _saveRecentSearch(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = [query, ..._recentSearches.where((s) => s != query)];
    final limited = updated.take(10).toList();
    setState(() => _recentSearches = limited);
    await prefs.setStringList('recent_location_searches', limited);
  }

  Future<void> _getSearchSuggestions(String query) async {
    if (query.trim().isEmpty || query.length < 3) return;

    setState(() => _isLoadingSuggestions = true);

    try {
      final locationService = ref.read(locationServiceProvider);
      final userLocation = ref.read(userLocationNotifierProvider);
      final suggestions = await locationService.getLocationSuggestions(
        query,
        mode: widget.mode,
        proximityLng: userLocation?.longitude,
        proximityLat: userLocation?.latitude,
      );

      if (mounted) {
        setState(() {
          _suggestions = suggestions;
          _isLoadingSuggestions = false;
        });
      }
    } catch (e) {
      debugPrint('Error getting suggestions: $e');
      if (mounted) {
        setState(() {
          _suggestions = [];
          _isLoadingSuggestions = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appBarTitle = _isAddressMode ? 'Search Address' : 'Search City';
    final label = _isAddressMode ? 'Street address' : 'City or area';
    final hint = _isAddressMode
        ? 'e.g., 123 Main St, New York'
        : 'e.g., New York or Lagos';

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(Spacing.lg.h),
            child: AppTextFormField(
              controller: _searchController,
              label: label,
              hintText: hint,
              prefixIcon: Icons.search,
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _suggestions = [];
                          _hasActiveQuery = false;
                        });
                      },
                    )
                  : null,
            ),
          ),

          Expanded(
            child: _isLoadingSuggestions
                ? const Center(child: CircularLoadingIndicator())
                : _suggestions.isNotEmpty
                    ? _buildSuggestionsList()
                    : _hasActiveQuery
                        ? _buildNoResults()
                        : _buildRecentSearchesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsList() {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: Spacing.lg.w),
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = _suggestions[index];
        final String displayText;

        if (suggestion is ParsedAddress) {
          displayText = suggestion.fullAddress;
        } else {
          displayText = suggestion.toString();
        }

        return ListTile(
          leading: Icon(
            Icons.location_on,
            color: Theme.of(context).colorScheme.primary,
            size: 20.sp,
          ),
          title: Text(
            displayText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: suggestion is ParsedAddress && suggestion.city != null
              ? Text(
                  [suggestion.city, suggestion.country]
                      .whereType<String>()
                      .join(', '),
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          onTap: () {
            if (suggestion is ParsedAddress) {
              _selectLocation(suggestion);
            } else {
              _getSearchSuggestions(displayText);
            }
          },
        );
      },
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 48.sp,
            color: Theme.of(context).colorScheme.outline,
          ),
          Gap(Spacing.md.h),
          Text(
            'No results found',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          Gap(Spacing.sm.h),
          Text(
            'Try a different search term',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSearchesList() {
    final colorScheme = Theme.of(context).colorScheme;
    if (_recentSearches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 48.sp,
              color: colorScheme.outline,
            ),
            Gap(Spacing.md.h),
            Text(
              'No recent searches',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            Gap(Spacing.sm.h),
            Text(
              'Search for a location above',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.all(Spacing.lg.h),
          child: Text(
            'Recent searches',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: Spacing.lg.w),
            itemCount: _recentSearches.length,
            itemBuilder: (context, index) {
              final search = _recentSearches[index];
              return ListTile(
                leading: Icon(
                  Icons.history,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                  size: 20.sp,
                ),
                title: Text(search),
                trailing: IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18.sp,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  onPressed: () {
                    setState(() => _recentSearches.removeAt(index));
                    _saveRecentSearchesToPrefs();
                  },
                ),
                onTap: () {
                  _searchController.text = search;
                  _getSearchSuggestions(search);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _saveRecentSearchesToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_location_searches', _recentSearches);
  }

  Future<void> _selectLocation(ParsedAddress address) async {
    final locationService = ref.read(locationServiceProvider);

    ParsedAddress resolved = address;
    if (address.latitude == null && address.placeId != null) {
      final details = await locationService.getPlaceDetails(address.placeId!);
      if (details == null) {
        if (mounted) _showNotFoundError();
        return;
      }
      resolved = details;
    }

    if (_isAddressMode) {
      await _saveRecentSearch(resolved.fullAddress);
      if (mounted) context.pop(resolved);
    } else {
      // Use the already-resolved ParsedAddress directly — avoids a redundant
      // second geocoding call (setSearchedLocation re-geocodes the query string
      // via the geocoding package, which can silently fail).
      final success = await ref
          .read(userLocationNotifierProvider.notifier)
          .setFromParsedAddress(resolved);

      if (success && mounted) {
        await _saveRecentSearch(resolved.fullAddress);
        if (mounted) Navigator.pop(context);
      } else if (mounted) {
        _showNotFoundError();
      }
    }
  }

  void _showNotFoundError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Location not found. Please try a different search.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debouncer.cancel();
    super.dispose();
  }
}
