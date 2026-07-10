import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';

class PhoneCountryPickerSheet extends StatefulWidget {
  const PhoneCountryPickerSheet({
    super.key,
    required this.selectedCountry,
    required this.onCountrySelected,
  });

  final PhoneCountry selectedCountry;
  final ValueChanged<PhoneCountry> onCountrySelected;

  @override
  State<PhoneCountryPickerSheet> createState() =>
      _PhoneCountryPickerSheetState();
}

class _PhoneCountryPickerSheetState extends State<PhoneCountryPickerSheet> {
  final _searchController = TextEditingController();
  List<PhoneCountry> _countries = PhoneCountries.all;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterCountries);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterCountries);
    _searchController.dispose();
    super.dispose();
  }

  void _filterCountries() {
    final query = _searchController.text;
    setState(() {
      _countries =
          PhoneCountries.all
              .where((country) => country.matches(query))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Spacing.lg.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BottomSheetHeader(title: ''),
              AppTextFormField(
                controller: _searchController,
                label: 'Search',
                hintText: 'Country or code',
                prefixIcon: Icons.search,
                textInputAction: TextInputAction.search,
              ),
            ],
          ),
        ),
        Gap(Spacing.md.h),
        Expanded(
          child:
              _countries.isEmpty
                  ? const EmptyStateWidget(
                    icon: Icons.search_off,
                    title: 'No country found',
                    subtitle: 'Try searching by country name or dial code.',
                  )
                  : ListView.separated(
                    padding: EdgeInsets.symmetric(horizontal: Spacing.lg.w),
                    itemCount: _countries.length,
                    separatorBuilder: (_, __) => Gap(Spacing.sm.h),
                    itemBuilder: (context, index) {
                      final country = _countries[index];
                      final selected =
                          country.isoCode == widget.selectedCountry.isoCode &&
                          country.dialCode == widget.selectedCountry.dialCode;

                      return SelectionTile(
                        title: '${country.flag} ${country.name}',
                        subtitle: '${country.dialCode} • ${country.isoCode}',
                        isSelected: selected,
                        onTap: () {
                          widget.onCountrySelected(country);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
        ),
      ],
    );
  }
}
