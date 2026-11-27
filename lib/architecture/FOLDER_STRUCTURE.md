## 🎯 Overview

This phase provides the complete project folder structure from root directory to individual files. Each file includes a purpose annotation to clarify its role in the architecture. This structure consolidates all previous phases (0-8) into a single, coherent tree.

## 📁 Root Directory Structure

```
nanoembryo/
├── .gitignore
├── README.md
├── pubspec.yaml
├── pubspec.lock
├── analysis_options.yaml
├── .env.example
│
├── assets/
│   ├── env/
│   │   ├── .env.development          # Dev environment variables
│   │   └── .env.production           # Prod environment variables
│   ├── fonts/                        # Custom font files
│   └── images/                       # Static app images
│
├── lib/
│   ├── main.dart                     # App entry point, Supabase init
│   ├── app.dart                      # Main App widget with ScreenUtil
│   ├── app_router.dart               # GoRouter configuration
│   │
│   ├── core/
│   │   ├── config/
│   │   │   └── environment.dart      # Environment variable manager
│   │   ├── design_tokens/
│   │   │   └── tokens.dart           # Centralized spacing, colors, typography
│   │   ├── network/
│   │   │   └── supabase_client_provider.dart
│   │   ├── services/
│   │   │   ├── location_service.dart # Geolocation handling
│   │   │   └── url_launcher_service.dart # Phone, email, maps launcher
│   │   ├── theme/
│   │   │   ├── app_colors.dart       # Light/Dark theme colors
│   │   │   ├── app_text_theme.dart   # Typography system
│   │   │   ├── app_theme.dart        # ThemeData configuration
│   │   │   └── design_tokens.dart    # Design system tokens
│   │   ├── utils/
│   │   │   ├── constants.dart        # App constants
│   │   │   ├── date_range_utils.dart # Date period calculations
│   │   │   ├── distance_formatter.dart
│   │   │   ├── exports.dart          # Centralized imports
│   │   │   ├── result.dart           # Result wrapper for error handling
│   │   │   └── screen_util_config.dart
│   │   └── widgets/
│   │       ├── app_button.dart
│   │       ├── app_filter_chip.dart
│   │       ├── app_text_form_field.dart
│   │       ├── card_inkwell.dart
│   │       ├── empty_state_widget.dart
│   │       ├── error_state_widget.dart
│   │       └── home_widget.dart      # Bottom navigation wrapper
│   │
│   ├── features/
│   │   │
│   │   ├── auth/
│   │   │   ├── providers/
│   │   │   │   └── auth_provider.dart # Authentication state
│   │   │   ├── screens/
│   │   │   │   ├── signup_screen.dart
│   │   │   │   └── forgot_password_screen.dart
│   │   │   └── widgets/
│   │   │       ├── social_login_buttons.dart
│   │   │       └── auth_form_field.dart
│   │   │
│   │   ├── bookings/
│   │   │   ├── data/
│   │   │   │   ├── models/
│   │   │   │   │   ├── booking_model.dart
│   │   │   │   │   ├── booking_service_model.dart
│   │   │   │   │   ├── booking_params.dart
│   │   │   │   │   ├── paginated_bookings.dart
│   │   │   │   │   └── time_slot.dart
│   │   │   │   └── repositories/
│   │   │   │       ├── booking_repository.dart
│   │   │   │       └── supabase_booking_repository.dart
│   │   │   ├── domain/
│   │   │   │   ├── entities/
│   │   │   │   │   ├── booking.dart
│   │   │   │   │   ├── booking_service.dart
│   │   │   │   │   └── booking_status.dart
│   │   │   │   ├── providers/
│   │   │   │   │   ├── booking_providers.dart
│   │   │   │   │   └── booking_draft_notifier.dart
│   │   │   │   └── repositories/
│   │   │   │       └── booking_repository.dart
│   │   │   └── presentation/
│   │   │       ├── screens/
│   │   │       │   ├── service_selection_screen.dart
│   │   │       │   ├── date_time_selection_screen.dart
│   │   │       │   ├── worker_assignment_screen.dart
│   │   │       │   ├── booking_summary_screen.dart
│   │   │       │   ├── booking_confirmation_screen.dart
│   │   │       │   └── booking_detail_screen.dart
│   │   │       └── widgets/
│   │   │           ├── client_service_card.dart
│   │   │           ├── time_slot_selector.dart
│   │   │           ├── booking_price_breakdown.dart
│   │   │           ├── worker_selector.dart
│   │   │           ├── group_booking_row.dart
│   │   │           └── booking_status_badge.dart
│   │   │
│   │   ├── calendar/
│   │   │   ├── data/
│   │   │   │   ├── models/
│   │   │   │   │   ├── client_calendar_booking.dart
│   │   │   │   │   └── shop_calendar_booking.dart
│   │   │   │   └── repositories/
│   │   │   │       └── supabase_calendar_repository.dart
│   │   │   ├── domain/
│   │   │   │   ├── providers/
│   │   │   │   │   └── calendar_provider.dart
│   │   │   │   └── repositories/
│   │   │   │       └── calendar_repository.dart
│   │   │   └── presentation/
│   │   │       ├── screens/
│   │   │       │   └── calendar_screen.dart
│   │   │       └── widgets/
│   │   │           ├── calendar_month_view.dart
│   │   │           ├── day_appointments_sheet.dart
│   │   │           ├── month_appointments_list.dart
│   │   │           └── shop_selector_dropdown.dart
│   │   │
│   │   ├── chat/
│   │   │   ├── data/
│   │   │   │   ├── models/
│   │   │   │   │   ├── sendbird/
│   │   │   │   │   │   ├── sb_channel.dart
│   │   │   │   │   │   ├── sb_message.dart
│   │   │   │   │   │   ├── sb_user.dart
│   │   │   │   │   │   └── sb_types.dart
│   │   │   │   │   ├── conversation.dart
│   │   │   │   │   └── message.dart
│   │   │   │   └── repositories/
│   │   │   │       └── sendbird_chat_repository.dart
│   │   │   ├── domain/
│   │   │   │   ├── entities/
│   │   │   │   │   ├── conversation.dart
│   │   │   │   │   └── message.dart
│   │   │   │   └── repositories/
│   │   │   │       └── chat_repository.dart
│   │   │   └── presentation/
│   │   │       ├── screens/
│   │   │       │   ├── chat_home_screen.dart
│   │   │       │   ├── conversations_screen.dart
│   │   │       │   └── chat_screen.dart
│   │   │       ├── state/
│   │   │       │   ├── chat_providers.dart
│   │   │       │   └── chat_controller.dart
│   │   │       └── widgets/
│   │   │           ├── message_bubble.dart
│   │   │           ├── typing_indicator.dart
│   │   │           ├── message_input_field.dart
│   │   │           ├── unread_badge.dart
│   │   │           └── channel_avatar.dart
│   │   │
│   │   ├── dashboard/
│   │   │   ├── data/
│   │   │   │   ├── models/
│   │   │   │   │   ├── analytics/
│   │   │   │   │   │   ├── quarterly_revenue.dart
│   │   │   │   │   │   ├── top_services_data.dart
│   │   │   │   │   │   └── top_workers_data.dart
│   │   │   │   │   ├── dashboard_metrics.dart
│   │   │   │   │   ├── booking_heatmap_models.dart
│   │   │   │   │   ├── client_management_models.dart
│   │   │   │   │   ├── revenue_comparison.dart
│   │   │   │   │   └── worker_performance.dart
│   │   │   │   └── repositories/
│   │   │   │       └── supabase_dashboard_repository.dart
│   │   │   ├── domain/
│   │   │   │   └── repositories/
│   │   │   │       └── dashboard_repository.dart
│   │   │   ├── presentation/
│   │   │   │   ├── controllers/
│   │   │   │   │   ├── owner_dashboard_controller.dart
│   │   │   │   │   ├── analytics_controller.dart
│   │   │   │   │   ├── heatmap_controller.dart
│   │   │   │   │   ├── client_management_controller.dart
│   │   │   │   │   ├── worker_management_controller.dart
│   │   │   │   │   └── export_controller.dart
│   │   │   │   ├── screens/
│   │   │   │   │   ├── owner_dashboard_screen.dart
│   │   │   │   │   ├── analytics_screen.dart
│   │   │   │   │   ├── insights_screen.dart
│   │   │   │   │   ├── tools_screen.dart
│   │   │   │   │   ├── clients_screen.dart
│   │   │   │   │   ├── client_detail_screen.dart
│   │   │   │   │   ├── workers_screen.dart
│   │   │   │   │   ├── worker_detail_screen.dart
│   │   │   │   │   └── service_detail_screen.dart
│   │   │   │   └── widgets/
│   │   │   │       ├── kpi_card.dart
│   │   │   │       ├── top_services_list.dart
│   │   │   │       ├── top_workers_list.dart
│   │   │   │       ├── booking_heatmap.dart
│   │   │   │       ├── heatmap_insights.dart
│   │   │   │       ├── quarterly_revenue_chart.dart
│   │   │   │       ├── client_card.dart
│   │   │   │       ├── worker_card.dart
│   │   │   │       ├── attendance_registry.dart
│   │   │   │       └── export_button.dart
│   │   │   └── shared/
│   │   │       └── providers/
│   │   │           └── dashboard_providers.dart
│   │   │
│   │   ├── discover/
│   │   │   ├── providers/
│   │   │   │   ├── discover_state_provider.dart
│   │   │   │   └── service_category_provider.dart
│   │   │   ├── screens/
│   │   │   │   └── discover_screen.dart
│   │   │   └── widgets/
│   │   │       ├── provider_type_tabs.dart
│   │   │       └── service_category_tabs.dart
│   │   │
│   │   ├── location/
│   │   │   ├── models/
│   │   │   │   └── user_location.dart
│   │   │   ├── providers/
│   │   │   │   └── location_provider.dart
│   │   │   ├── screens/
│   │   │   │   └── location_search_screen.dart
│   │   │   └── widgets/
│   │   │       ├── location_display_widget.dart
│   │   │       └── location_picker_bottom_sheet.dart
│   │   │
│   │   ├── map/
│   │   │   ├── data/
│   │   │   │   ├── models/
│   │   │   │   │   └── shop_location_dto.dart
│   │   │   │   ├── repositories/
│   │   │   │   │   └── map_repository_impl.dart
│   │   │   │   └── datasources/
│   │   │   │       └── supabase_map_datasource.dart
│   │   │   ├── domain/
│   │   │   │   ├── entities/
│   │   │   │   │   └── map_bounds.dart
│   │   │   │   └── repositories/
│   │   │   │       └── map_repository.dart
│   │   │   └── presentation/
│   │   │       ├── controllers/
│   │   │       │   └── map_controller.dart
│   │   │       ├── providers/
│   │   │       │   ├── map_providers.dart
│   │   │       │   └── map_filter_providers.dart
│   │   │       ├── screens/
│   │   │       │   └── map_screen.dart
│   │   │       └── widgets/
│   │   │           ├── canvas_marker_builder.dart
│   │   │           ├── shop_info_bottom_sheet.dart
│   │   │           ├── map_filter_bar.dart
│   │   │           └── user_location_button.dart
│   │   │
│   │   ├── reviews/
│   │   │   ├── data/
│   │   │   │   ├── models/
│   │   │   │   │   ├── booking_review.dart
│   │   │   │   │   ├── review_rating.dart
│   │   │   │   │   └── shop_rating.dart
│   │   │   │   └── repositories/
│   │   │   │       └── supabase_review_repository.dart
│   │   │   ├── domain/
│   │   │   │   ├── providers/
│   │   │   │   │   └── review_providers.dart
│   │   │   │   └── repositories/
│   │   │   │       └── review_repository.dart
│   │   │   └── presentation/
│   │   │       ├── controllers/
│   │   │       │   ├── review_submission_controller.dart
│   │   │       │   └── shop_response_controller.dart
│   │   │       ├── screens/
│   │   │       │   └── review_submission_screen.dart
│   │   │       └── widgets/
│   │   │           ├── star_rating_widget.dart
│   │   │           ├── review_bottom_sheet.dart
│   │   │           ├── review_display_widget.dart
│   │   │           ├── shop_rating_widget.dart
│   │   │           ├── detailed_shop_rating_widget.dart
│   │   │           └── rating_distribution_bars.dart
│   │   │
│   │   ├── search/
│   │   │   ├── data/
│   │   │   │   ├── local/
│   │   │   │   │   └── search_history_storage.dart
│   │   │   │   └── repositories/
│   │   │   │       ├── shop_search_repository.dart
│   │   │   │       ├── profile_search_repository.dart
│   │   │   │       └── unified_search_repository.dart
│   │   │   ├── domain/
│   │   │   │   ├── mappers/
│   │   │   │   │   └── shop_to_search_mapper.dart
│   │   │   │   └── repositories/
│   │   │   │       └── search_repository.dart
│   │   │   ├── models/
│   │   │   │   ├── search_category.dart
│   │   │   │   ├── search_filters.dart
│   │   │   │   ├── search_paginated_result.dart
│   │   │   │   ├── unified_search_result.dart
│   │   │   │   ├── shop_search_result.dart
│   │   │   │   ├── profile_search_result.dart
│   │   │   │   └── category_search_section.dart
│   │   │   ├── presentation/
│   │   │   │   ├── screens/
│   │   │   │   │   ├── search_screen.dart
│   │   │   │   │   └── category_results_screen.dart
│   │   │   │   ├── state/
│   │   │   │   │   └── search_providers.dart
│   │   │   │   └── widgets/
│   │   │   │       ├── category_filter_chips.dart
│   │   │   │       ├── category_result_card.dart
│   │   │   │       ├── horizontal_shop_list.dart
│   │   │   │       ├── search_suggestions.dart
│   │   │   │       └── search_app_bar.dart
│   │   │   └── utils/
│   │   │       └── search_analytics.dart
│   │   │
│   │   ├── shop_daily_schedule/
│   │   │   ├── data/
│   │   │   │   ├── models/
│   │   │   │   │   ├── time_group.dart
│   │   │   │   │   └── grouped_appointments.dart
│   │   │   │   └── repositories/
│   │   │   │       └── supabase_daily_schedule_repository.dart
│   │   │   ├── domain/
│   │   │   │   ├── providers/
│   │   │   │   │   └── daily_schedule_provider.dart
│   │   │   │   └── repositories/
│   │   │   │       └── daily_schedule_repository.dart
│   │   │   └── presentation/
│   │   │       ├── screens/
│   │   │       │   ├── daily_schedule_screen.dart
│   │   │       │   └── shop_schedule_hub.dart
│   │   │       └── widgets/
│   │   │           ├── horizontal_date_selector.dart
│   │   │           ├── time_group_filter_chips.dart
│   │   │           ├── appointment_card.dart
│   │   │           └── appointment_bottom_sheet.dart
│   │   │
│   │   └── shops/
│   │       ├── data/
│   │       │   ├── dtos/
│   │       │   │   ├── shop_list_item_dto.dart
│   │       │   │   ├── shop_details_dto.dart
│   │       │   │   ├── shop_media_dto.dart
│   │       │   │   ├── appointment_slot_dto.dart
│   │       │   │   └── opening_hours_dto.dart
│   │       │   ├── models/
│   │       │   │   ├── shop.dart
│   │       │   │   ├── worker.dart
│   │       │   │   ├── appointment_slot_model.dart
│   │       │   │   └── shop_type_count.dart
│   │       │   ├── local/
│   │       │   │   └── shop_draft_storage.dart
│   │       │   └── repositories/
│   │       │       └── supabase_shop_repository.dart
│   │       ├── domain/
│   │       │   ├── entities/
│   │       │   │   └── shop.dart
│   │       │   └── repositories/
│   │       │       └── shop_repository.dart
│   │       ├── presentation/
│   │       │   ├── providers/
│   │       │   │   ├── shop_repository_provider.dart
│   │       │   │   ├── shop_draft_provider.dart
│   │       │   │   ├── shop_details_provider.dart
│   │       │   │   ├── shop_list_provider.dart
│   │       │   │   └── luxury_level_provider.dart
│   │       │   ├── screens/
│   │       │   │   ├── creation/
│   │       │   │   │   ├── basic_info_screen.dart
│   │       │   │   │   ├── services_screen.dart
│   │       │   │   │   ├── opening_hours_screen.dart
│   │       │   │   │   ├── media_screen.dart
│   │       │   │   │   └── review_publish_screen.dart
│   │       │   │   ├── edit/
│   │       │   │   │   └── edit_shop_screen.dart
│   │       │   │   ├── dashboard/
│   │       │   │   │   └── shop_dashboard_screen.dart
│   │       │   │   └── details/
│   │       │   │       └── shop_details_screen.dart
│   │       │   └── widgets/
│   │       │       ├── shop_card.dart
│   │       │       ├── worker_card.dart
│   │       │       ├── service_card.dart
│   │       │       ├── opening_hours_row.dart
│   │       │       ├── image_reorder_grid.dart
│   │       │       └── currency_picker.dart
│   │       ├── payment/
│   │       │   ├── data/
│   │       │   │   ├── models/
│   │       │   │   │   └── payment_settings_model.dart
│   │       │   │   └── repositories/
│   │       │   │       └── payment_settings_repository.dart
│   │       │   ├── presentation/
│   │       │   │   ├── controllers/
│   │       │   │   │   └── payment_settings_controller.dart
│   │       │   │   ├── screens/
│   │       │   │   │   └── payment_settings_screen.dart
│   │       │   │   └── widgets/
│   │       │   │       ├── paystack_connection_card.dart
│   │       │   │       ├── stripe_connection_card.dart
│   │       │   │       └── fee_info_card.dart
│   │       │   └── providers/
│   │       │       └── payment_setup_provider.dart
│   │       └── wallet/
│   │           ├── data/
│   │           │   ├── models/
│   │           │   │   ├── wallet_model.dart
│   │           │   │   ├── wallet_transaction_model.dart
│   │           │   │   └── withdrawal_request_model.dart
│   │           │   ├── repositories/
│   │           │   │   └── supabase_wallet_repository.dart
│   │           │   └── exceptions/
│   │           │       └── wallet_exceptions.dart
│   │           ├── presentation/
│   │           │   ├── controllers/
│   │           │   │   └── wallet_controller.dart
│   │           │   ├── screens/
│   │           │   │   └── wallet_screen.dart
│   │           │   └── widgets/
│   │           │       ├── wallet_balance_card.dart
│   │           │       ├── transaction_list_item.dart
│   │           │       └── withdrawal_sheet.dart
│   │           └── providers/
│   │               └── wallet_providers.dart
│   │
│   ├── l10n/
│   │   ├── app_en.arb                 # English localization strings
│   │   ├── app_es.arb                 # Spanish localization (example)
│   │   └── generated/                 # Auto-generated localization files
│   │
│   └── presentation/
│       ├── features/
│       │   ├── intro/
│       │   │   ├── intro_screen.dart
│       │   │   └── models/
│       │   │       └── intro_page.dart
│       │   └── home/
│       │       └── home_screen.dart
│       └── shared/
│           └── widgets/
│               ├── settings/
│               │   ├── settings_section.dart
│               │   └── settings_item.dart
│               └── tabs/
│                   ├── simple_tabs.dart
│                   └── tabs_with_content.dart
│
├── supabase/
│   └── functions/
│       ├── paystack-subaccount/
│       │   ├── index.ts
│       │   └── package.json
│       ├── stripe-connect/
│       │   ├── index.ts
│       │   └── package.json
│       └── process-withdrawal/
│           ├── index.ts
│           └── package.json
│
├── ios/
│   ├── Runner/
│   │   ├── Info.plist                # Mapbox token configuration
│   │   └── GoogleService-Info.plist  # (if using Firebase)
│   └── Podfile
│
├── android/
│   ├── app/
│   │   └── src/
│   │       └── main/
│   │           └── AndroidManifest.xml # Mapbox token configuration
│   └── gradle.properties             # MAPBOX_ACCESS_TOKEN
│
├── web/
│   └── index.html
│
└── test/
    ├── unit/                         # Unit tests
    ├── widget/                       # Widget tests
    └── integration/                  # Integration tests
```

## 📊 Phase Dependencies Summary

| Phase   | Feature                  | Dependencies                       |
| ------- | ------------------------ | ---------------------------------- |
| Phase 0 | Foundation & Quick Start | None                               |
| Phase 1 | Shop Management          | Phase 0                            |
| Phase 2 | Discovery & Search       | Phase 0, Phase 1                   |
| Phase 3 | Booking System           | Phase 0, Phase 1                   |
| Phase 4 | Payment & Wallet         | Phase 0, Phase 1, Phase 3          |
| Phase 5 | Calendar & Schedule      | Phase 0, Phase 1, Phase 3          |
| Phase 6 | Shop Owner Dashboard     | Phase 0, Phase 1, Phase 3, Phase 4 |
| Phase 7 | Review & Rating System   | Phase 0, Phase 1, Phase 3          |
| Phase 8 | Chat System              | Phase 0, Phase 1, Phase 3          |

## ✅ Architecture Completion

This completes the NanoEmbryo Architecture Documentation. The project is structured as a production-ready Flutter application with:

- **9 Phases** covering all features from foundation to chat
- **Clear dependency ordering** ensuring features build on each other
- **Consistent patterns** across repositories, providers, and UI components
- **Database-first design** with PostgreSQL, PostGIS, and RLS policies
- **Edge Functions** for secure payment provider integration
- **Complete folder structure** with every file accounted for
