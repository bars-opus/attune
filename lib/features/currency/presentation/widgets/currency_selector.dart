import 'package:attune/core/utils/location/widgets/highlight_container.dart';
import 'package:attune/core/widgets/search_text_field.dart';
import 'package:attune/features/auth/utility/auth_exports.dart';
import 'package:attune/features/currency/domain/entities/currency.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';

class CurrencySelector extends StatelessWidget {
  final Currency? selectedCurrency;
  final Function(Currency) onCurrencySelected;
  final String? errorText;
  final List<Currency>? availableCurrencies; // For multi-currency countries

  const CurrencySelector({
    super.key,
    required this.selectedCurrency,
    required this.onCurrencySelected,
    this.errorText,
    this.availableCurrencies,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencies = availableCurrencies ?? Currencies.all;
    final colorScheme = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;

    // Display the selected currency or placeholder with flag
    return HighlightContainer(
      child: InfoRowWidget(
        // Show selected currency with flag or placeholder
        title:
            selectedCurrency != null
                ? '${selectedCurrency!.flag} ${selectedCurrency!.code} (${selectedCurrency!.symbol})'
                : loc.currencySelectorPlaceholder,
        subtitle: selectedCurrency?.name ?? loc.currencySelectorNoSelected,
        icon: Icons.currency_exchange_outlined,
        avatarRadius: 25.h,
        backgroundColor: colorScheme.primary,
        iconColor: colorScheme.primary,
        onTap: () => _showCurrencyPicker(context, currencies),
        disableTrailing: false,
        showAvatar: false,
        showDivider: false,
        showTrailingArrow: true,
        trailing: AppIconButton(
          icon: Icons.add,
          onPressed: () => _showCurrencyPicker(context, currencies),
        ),
      ),
    );
  }

  /// Show currency picker bottom sheet with search
  Future<void> _showCurrencyPicker(
    BuildContext context,
    List<Currency> currencies,
  ) async {
    final selected = await showModalBottomSheet<Currency>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => CurrencyPickerSheet(
            currencies: currencies,
            selectedCurrency: selectedCurrency,
          ),
    );

    if (selected != null) {
      onCurrencySelected(selected);
    }
  }
}

/// Currency picker bottom sheet with search
class CurrencyPickerSheet extends StatefulWidget {
  final List<Currency> currencies;
  final Currency? selectedCurrency;

  const CurrencyPickerSheet({
    super.key,
    required this.currencies,
    this.selectedCurrency,
  });

  @override
  State<CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<CurrencyPickerSheet> {
  late List<Currency> _filteredCurrencies;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredCurrencies = widget.currencies;
    _searchController.addListener(_filterCurrencies);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterCurrencies);
    _searchController.dispose();
    super.dispose();
  }

  void _filterCurrencies() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredCurrencies = widget.currencies;
      } else {
        _filteredCurrencies =
            widget.currencies.where((currency) {
              return currency.name.toLowerCase().contains(query) ||
                  currency.code.toLowerCase().contains(query) ||
                  currency.flag.contains(query);
            }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;

    return Container(
      height: 700.h,
      padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with handle
          Container(
            padding: EdgeInsets.all(Spacing.sm.h),
            child: Center(
              child: Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
            ),
          ),

          // Title
          Padding(
            padding: EdgeInsets.all(Spacing.md.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  loc.currencySelectorTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onBackground,
                  ),
                ),
                AppTextButton(),
              ],
            ),
          ),
          SearchFormField(

            controller: _searchController,
            // focusNode: _searchFocusNode,
            autofocus: false,
            hintText: loc.currencySelectorSearchHint,
            showClearButton: true,

            //  _searchController.text.isNotEmpty
            //             ? IconButton(
            //               icon: Icon(Icons.clear, size: 16.sp),
            //               onPressed: () {
            //                 _searchController.clear();
            //               },
            //             )
            //             : null,,
            // filterChips: _availableFilters,
            // selectedFilters: _selectedFilters,
            // onFiltersChanged: _handleFiltersChanged,
            // onSearchSubmitted: _handleSearchSubmitted,
            // onCancelPressed: _toggleSearch,
            // onSearchChanged: (query) {
            //   ref.read(searchQueryProvider.notifier).state = query;
            // },
          ),
          Gap(Spacing.sm.h),

          // Currency list
          Expanded(
            child:
                _filteredCurrencies.isEmpty
                    ? Center(
                      child: EmptyStateWidget(
                        icon: Icons.money_off_outlined,
                        subtitle: loc.currencySelectorNoResults,
                      ),
                    )
                    : ListView.builder(
                      itemCount: _filteredCurrencies.length,
                      itemBuilder: (context, index) {
                        final currency = _filteredCurrencies[index];
                        final isSelected =
                            widget.selectedCurrency?.code == currency.code;

                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: Spacing.xs),
                          child: HighlightContainer(
                            padding: 0,
                            color:
                                isSelected
                                    ? colorScheme.primary.withOpacity(0.1)
                                    : Colors.transparent,
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: Spacing.xs,
                                horizontal: Spacing.md,
                              ),
                              child: InfoRowWidget(
                                title: currency.name,
                                subtitle:
                                    '${currency.code} (${currency.symbol})',
                                icon: Icons.check_circle,
                                iconSize: isSelected ? 30.h : 0,
                                backgroundColor:
                                    isSelected ? colorScheme.primary : null,
                                iconColor:
                                    isSelected
                                        ? colorScheme.primary
                                        : Colors.transparent,
                                onTap: () => Navigator.pop(context, currency),
                                disableTrailing: false,
                                showAvatar: false,
                                showDivider: false,
                                showTrailingArrow: true,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      currency.symbol,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color:
                                                isSelected
                                                    ? colorScheme.primary
                                                    : colorScheme.onSurface,
                                          ),
                                    ),
                                    Gap(Spacing.xs.w),
                                    Text(
                                      currency.flag,
                                      style: TextStyle(fontSize: 24.sp),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
