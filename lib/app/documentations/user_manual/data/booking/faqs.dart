// lib/features/documentation/data/docs/booking_docs/faqs.dart

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class FAQsDocs implements DocumentationModule {
  @override
  int get order => 6;

  @override
  String getTitle(BuildContext context) => 'Frequently Asked Questions';

  @override
  String get id => 'faqs';

  @override
  String getSubtitle(BuildContext context) =>
      'Quick answers to common questions about bookings';

  @override
  IconData get icon => Icons.help_outline;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'faq_getting_started',
      title: 'Getting Started',
      subtitle: 'New to the app? Start here',
      icon: Icons.rocket_launch,
      category: 'FAQs',
      order: 1,
      contents: [
        ManualContent(
          id: 'faq_gs_list',
          title: 'Common Questions',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Do I need an account to book?** – Yes, you need an account to book appointments. You can browse shops and services without an account, but booking requires sign-in.',
            '**Is the app free to use?** – Yes! The app is completely free for clients. Shop owners pay a small commission on each booking.',
            '**How do I create an account?** – Download the app, tap "Sign Up", enter your email and create a password. Verify your email and you\'re ready to go!',
            '**Can I use the app without an account?** – You can browse shops and services, but you\'ll need an account to actually book appointments.',
          ],
        ),
      ],
    ),
    ManualSection(
      id: 'faq_booking_process',
      title: 'Booking Process',
      subtitle: 'Questions about making bookings',
      icon: Icons.event,
      category: 'FAQs',
      order: 2,
      contents: [
        ManualContent(
          id: 'faq_booking_list',
          title: 'Common Booking Questions',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**How far in advance can I book?** – You can book up to 30 days in advance. Some shops may allow longer booking windows.',
            '**Can I book multiple services at once?** – Yes! You can select multiple services (e.g., haircut + beard trim) and book them together.',
            '**What\'s the difference between Regular and Combined view?** – Regular view shows slots for each service separately. Combined view shows only slots where all your services can be done together.',
            '**How is my total appointment time calculated?** – The system adds up all service durations, plus buffer time between services (usually 5-15 minutes).',
            '**Can I book for someone else?** – Yes! Use the quantity feature to book for multiple people. You can assign different workers to each person.',
            '**Why are some times not available?** – Times may be unavailable because the worker is booked, the shop is closed, or there\'s not enough time before closing.',
          ],
        ),
      ],
    ),
    ManualSection(
      id: 'faq_payment',
      title: 'Payment & Fees',
      subtitle: 'All your money questions answered',
      icon: Icons.payment,
      category: 'FAQs',
      order: 3,
      contents: [
        ManualContent(
          id: 'faq_payment_list',
          title: 'Common Payment Questions',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Why do I need to pay a deposit?** – The 30% deposit secures your slot and compensates workers if you cancel last minute. It\'s applied to your total bill.',
            '**Is the deposit refundable?** – No, the deposit is non-refundable if you cancel or don\'t show up. It is refunded only if the shop cancels.',
            '**What is the platform fee?** – A small fixed fee (e.g., GHS 2) charged by the app to maintain the platform. It\'s charged once per booking, not per service.',
            '**When do I pay the remaining 70%?** – After your service is complete. You can pay in cash or through the app.',
            '**Can I pay the remaining balance in cash?** – Yes! Cash is accepted at most shops. You can also pay through the app if you prefer.',
            '**What payment methods are accepted?** – Credit/debit cards, mobile money, bank transfers for deposits. Cash or app payments for remaining balance.',
            '**How do tips work?** – You can tip your worker in cash or add a tip when paying the remaining 70% through the app. 100% of tips go to the worker.',
            '**Is there a fee for group bookings?** – The platform fee is charged once per group booking (e.g., GHS 2 total), not per person. This saves you money!',
          ],
        ),
      ],
    ),
    ManualSection(
      id: 'faq_group_bookings',
      title: 'Group Bookings',
      subtitle: 'Booking for family and friends',
      icon: Icons.group,
      category: 'FAQs',
      order: 4,
      contents: [
        ManualContent(
          id: 'faq_group_list',
          title: 'Common Group Booking Questions',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**How do I book for multiple people?** – Select a service, then use the **+** button to increase the quantity. You can set different quantities for different services.',
            '**Can different people have different workers?** – Yes! After setting quantities, you\'ll see each person listed. Tap on each to choose their preferred worker.',
            '**How is the total time calculated for groups?** – The system adds: (service duration × quantity) + buffer times between people. If workers work in parallel, time may be shorter.',
            '**How is payment handled for groups?** – The deposit (30% of total) and platform fee are paid by the booker. After service, you can split the remaining 70% however you like.',
            '**What if one person cancels?** – Their portion of the deposit is forfeited. The rest of the group can proceed. Contact the shop to adjust.',
            '**Can we have different services for different people?** – Yes! Select each service and set quantities accordingly. For example: 2 haircuts + 1 braid service.',
            '**Is there a maximum group size?** – Each service has a maximum quantity limit shown when booking. For very large groups, you may need multiple bookings.',
          ],
        ),
      ],
    ),
    ManualSection(
      id: 'faq_workers',
      title: 'Workers & Services',
      subtitle: 'Questions about who does your service',
      icon: Icons.people,
      category: 'FAQs',
      order: 5,
      contents: [
        ManualContent(
          id: 'faq_workers_list',
          title: 'Common Worker Questions',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Can I choose my worker?** – For services with "Choose worker" option, yes! You\'ll see a list of available workers with their photos, specialties, and ratings.',
            '**What if my preferred worker isn\'t available?** – You can choose a different time when they\'re available, select another worker, or try a different date.',
            '**Can I change workers after booking?** – Yes, up to 24 hours before your appointment. Go to "My Bookings" and look for the change worker option.',
            '**How do I know if a worker is good?** – Each worker has a rating (out of 5) and reviews from previous clients. You can see these before choosing.',
            '**What if I don\'t choose a worker?** – For services that require worker selection, you must choose one. For others, the shop will assign an available worker.',
            '**Can the same worker serve multiple people in my group?** – Yes! You can assign the same worker to multiple people. They will serve them one after another.',
          ],
        ),
      ],
    ),
    ManualSection(
      id: 'faq_time_slots',
      title: 'Time Slots',
      subtitle: 'Understanding appointment times',
      icon: Icons.access_time,
      category: 'FAQs',
      order: 6,
      contents: [
        ManualContent(
          id: 'faq_time_list',
          title: 'Common Time Slot Questions',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Why do I see two views (Regular vs Combined)?** – Regular view shows slots for each service separately. Combined view shows only slots where all your services fit together. Use the toggle to switch.',
            '**Why are times shown in my local timezone?** – The app automatically converts all times to your device\'s local timezone. No need to calculate!',
            '**What is buffer time?** – Buffer time (5-15 minutes) between appointments allows workers to clean and prepare. You won\'t see it, but it\'s built into the schedule.',
            '**Why can\'t I book the last slot of the day?** – The slot must end before closing time, including buffer. The system automatically ensures this.',
            '**What if I need more time than the slot shows?** – Contact the shop directly. They may have special arrangements for complex services.',
            '**Why did a slot disappear while I was booking?** – Someone else may have booked it while you were deciding. Slots are reserved only after payment.',
            '**Are times shown in 12-hour or 24-hour format?** – Times are shown in 12-hour format (e.g., 9:00 AM) for easy reading.',
          ],
        ),
      ],
    ),
    ManualSection(
      id: 'faq_managing',
      title: 'Managing Your Bookings',
      subtitle: 'After you\'ve booked',
      icon: Icons.bookmarks,
      category: 'FAQs',
      order: 7,
      contents: [
        ManualContent(
          id: 'faq_manage_list',
          title: 'Common Management Questions',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**How do I view my bookings?** – Go to "My Bookings" in the app. You\'ll see all upcoming and past appointments.',
            '**How do I cancel a booking?** – Find the booking in "My Bookings", tap "Cancel". You can cancel up to 24 hours before. Deposit is non-refundable.',
            '**How do I reschedule?** – Find the booking, tap "Reschedule", and choose a new time. Deposit transfers to the new booking.',
            '**Will I get reminders?** – Yes! You\'ll receive reminders 24 hours and 1 hour before your appointment.',
            '**What if I\'m running late?** – Contact the shop through the app to let them know. They may be able to adjust.',
            '**How do I leave a review?** – After your appointment, you\'ll get a notification to rate your experience. You can also go to past bookings and leave a review.',
            '**Can I see my payment history?** – Yes, go to Profile → Payment History to see all transactions.',
            '**How do I get a receipt?** – Receipts are emailed automatically and available in Payment History.',
          ],
        ),
      ],
    ),
    ManualSection(
      id: 'faq_cancellation',
      title: 'Cancellation & Refunds',
      subtitle: 'When plans change',
      icon: Icons.cancel,
      category: 'FAQs',
      order: 8,
      contents: [
        ManualContent(
          id: 'faq_cancel_list',
          title: 'Common Cancellation Questions',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**What is your cancellation policy?** – You can cancel up to 24 hours before your appointment. The 30% deposit and platform fee are non-refundable.',
            '**Can I get a refund if I cancel?** – No, deposits and fees are non-refundable if you cancel. They are refunded only if the shop cancels.',
            '**What if I have an emergency?** – Contact the shop directly through the app. Some shops may offer credit toward a future booking at their discretion.',
            '**What happens if I don\'t show up?** – You\'re marked as a "no-show", the deposit is forfeited, and repeated no-shows may affect your account.',
            '**What if the shop cancels?** – If the shop cancels, you receive a full refund of your deposit and platform fee.',
            '**Can I reschedule instead of cancel?** – Yes! Rescheduling transfers your deposit to the new time. Much better than losing it!',
            '**How do I cancel a group booking?** – Same as individual bookings. If one person cancels, their portion of the deposit is forfeited.',
          ],
        ),
      ],
    ),
    ManualSection(
      id: 'faq_account',
      title: 'Account & Profile',
      subtitle: 'Your account questions',
      icon: Icons.account_circle,
      category: 'FAQs',
      order: 9,
      contents: [
        ManualContent(
          id: 'faq_account_list',
          title: 'Common Account Questions',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**How do I change my password?** – Go to Profile → Settings → Change Password.',
            '**How do I update my email?** – Go to Profile → Settings → Email. You\'ll need to verify the new email.',
            '**Can I have multiple accounts?** – One account per person is recommended. All your bookings are in one place.',
            '**How do I delete my account?** – Go to Profile → Settings → Delete Account. This is permanent and cannot be undone.',
            '**Is my information secure?** – Yes! We use industry-standard encryption and security practices.',
            '**Can I save payment methods?** – Yes, in Profile → Payment Methods. Your information is stored securely.',
            '**How do I change my notification settings?** – Go to Profile → Settings → Notifications.',
          ],
        ),
      ],
    ),
    ManualSection(
      id: 'faq_troubleshooting',
      title: 'Troubleshooting',
      subtitle: 'Having issues? Check here',
      icon: Icons.troubleshoot,
      category: 'FAQs',
      order: 10,
      contents: [
        ManualContent(
          id: 'faq_trouble_list',
          title: 'Common Issues & Solutions',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**App is slow or crashing** – Try closing and reopening the app. Check for updates in your app store.',
            '**Can\'t find a shop or service** – Use the search function. Make sure you\'re in the right location.',
            '**Payment not going through** – Check your internet connection. Verify your payment details. Try a different payment method.',
            '**Not receiving notifications** – Check your phone\'s notification settings. Ensure notifications are enabled for the app.',
            '**Booking disappeared** – Check "My Bookings" and filter by date. It may have been cancelled or completed.',
            '**Wrong time shown** – Times are in your local timezone. Check your device timezone settings.',
            '**Can\'t log in** – Try "Forgot Password" to reset. Check your email for verification if new account.',
          ],
        ),
      ],
    ),
    ManualSection(
      id: 'faq_contact',
      title: 'Contact & Support',
      subtitle: 'When you need help',
      icon: Icons.support_agent,
      category: 'FAQs',
      order: 11,
      contents: [
        ManualContent(
          id: 'faq_contact_list',
          title: 'How to Get Help',
          content: '',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**In-app support** – Go to Profile → Help & Support to chat with our team',
            '**Email support** – support@yourapp.com (response within 24 hours)',
            '**Phone support** – +233 XXX XXX XXX (Mon-Fri, 9am-5pm)',
            '**Shop contact** – For booking-specific issues, contact the shop directly through the app',
            '**FAQs** – Check this section first – your question may already be answered!',
          ],
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_main_cancel',
        question: 'Can I cancel my booking?',
        answer:
            'Yes, you can cancel up to 24 hours before your appointment. Go to "My Bookings", find your booking, and tap "Cancel". Please note that the 30% deposit and platform fee are non-refundable.',
        category: 'Cancellation',
        order: 1,
      ),
      FAQModel(
        id: 'faq_main_reschedule',
        question: 'How do I reschedule?',
        answer:
            'Find your booking in "My Bookings", tap "Reschedule", and choose a new time. Your deposit will transfer to the new booking. You can reschedule up to 24 hours before your appointment.',
        category: 'Managing Bookings',
        order: 2,
      ),
      FAQModel(
        id: 'faq_main_deposit',
        question: 'Why is there a deposit?',
        answer:
            'The 30% deposit secures your slot and compensates workers if you cancel last minute. It\'s applied to your total bill – you\'re not paying extra, just paying part of it upfront.',
        category: 'Payment',
        order: 3,
      ),
      FAQModel(
        id: 'faq_main_platform_fee',
        question: 'What is the platform fee?',
        answer:
            'The platform fee (e.g., GHS 2) is a small fixed charge by the app to maintain the platform. It\'s charged once per booking, not per service or per person. Group bookings pay just one fee!',
        category: 'Payment',
        order: 4,
      ),
      FAQModel(
        id: 'faq_main_remaining',
        question: 'How do I pay the remaining balance?',
        answer:
            'After your service, you can pay the remaining 70% in cash directly to the shop, or through the app using your preferred payment method. Both options are available.',
        category: 'Payment',
        order: 5,
      ),
      FAQModel(
        id: 'faq_main_group',
        question: 'How do group bookings work?',
        answer:
            'Select a service and use the **+** button to increase quantity. You can choose different workers for each person. Payment: 30% deposit on total, one platform fee for the whole group, remaining 70% split however you like after service.',
        category: 'Group Bookings',
        order: 6,
      ),
      FAQModel(
        id: 'faq_main_workers',
        question: 'Can I choose my worker?',
        answer:
            'For services with the "Choose worker" option, yes! You\'ll see photos, specialties, and ratings to help you decide. For group bookings, you can choose different workers for each person.',
        category: 'Workers',
        order: 7,
      ),
      FAQModel(
        id: 'faq_main_regular_vs_combined',
        question: 'Regular vs Combined view – what\'s the difference?',
        answer:
            'Regular view shows slots for each service separately. Combined view shows only slots where all your services can be done together. Use the toggle to switch. Combined view is best when you\'re ready to book multiple services.',
        category: 'Time Slots',
        order: 8,
      ),
      FAQModel(
        id: 'faq_main_timezone',
        question: 'What timezone are times shown in?',
        answer:
            'All times are automatically converted to your device\'s local timezone. You don\'t need to worry about timezone conversions – what you see is what you get!',
        category: 'Time Slots',
        order: 9,
      ),
      FAQModel(
        id: 'faq_main_refund',
        question: 'When do I get a refund?',
        answer:
            'Refunds are issued only if the shop cancels your booking. In that case, your full deposit and platform fee are returned. If you cancel, deposits and fees are non-refundable.',
        category: 'Payment',
        order: 10,
      ),
      FAQModel(
        id: 'faq_main_support',
        question: 'How do I contact support?',
        answer:
            'You can reach us through:\n'
            '• In-app: Profile → Help & Support\n'
            '• Email: support@yourapp.com\n'
            '• Phone: +233 XXX XXX XXX (Mon-Fri, 9am-5pm)\n\n'
            'For booking-specific issues, you can also message the shop directly through the app.',
        category: 'Support',
        order: 11,
      ),
      FAQModel(
        id: 'faq_main_no_show',
        question: 'What happens if I don\'t show up?',
        answer:
            'If you miss your appointment without cancelling, you\'re marked as a "no-show". The deposit is forfeited, and repeated no-shows may result in restrictions on your account. Always cancel if you can\'t make it!',
        category: 'Cancellation',
        order: 12,
      ),
      FAQModel(
        id: 'faq_main_multiple_services',
        question: 'Can I book multiple services at once?',
        answer:
            'Absolutely! Select all the services you want – the system will find time slots where they can all be done together. Use Combined View to see these options.',
        category: 'Booking Process',
        order: 13,
      ),
      FAQModel(
        id: 'faq_main_payment_methods',
        question: 'What payment methods are accepted?',
        answer:
            'For deposits: Credit/debit cards, mobile money, bank transfers. For remaining balance: Cash or any of the digital methods through the app. Available options may vary by region.',
        category: 'Payment',
        order: 14,
      ),
      FAQModel(
        id: 'faq_main_tip',
        question: 'How do I tip my worker?',
        answer:
            'You can tip in cash directly to your worker, or add a tip when paying the remaining 70% through the app. 100% of tips go to your worker!',
        category: 'Payment',
        order: 15,
      ),
      FAQModel(
        id: 'faq_main_receipt',
        question: 'How do I get a receipt?',
        answer:
            'Receipts are emailed to you automatically. You can also access all receipts in the app under Profile → Payment History. Each receipt shows full transaction details.',
        category: 'Account',
        order: 16,
      ),
      FAQModel(
        id: 'faq_main_change_worker',
        question: 'Can I change my worker after booking?',
        answer:
            'Yes, you can change your worker up to 24 hours before the appointment. Go to "My Bookings", find your booking, and look for the change worker option. The new worker must be available at your booked time.',
        category: 'Workers',
        order: 17,
      ),
      FAQModel(
        id: 'faq_main_buffer',
        question: 'What is buffer time?',
        answer:
            'Buffer time (5-15 minutes) is built into the schedule between appointments. It gives workers time to clean their station and prepare for the next client. You won\'t see it, but it ensures quality service for everyone.',
        category: 'Time Slots',
        order: 18,
      ),
      FAQModel(
        id: 'faq_main_account_delete',
        question: 'How do I delete my account?',
        answer:
            'Go to Profile → Settings → Delete Account. This action is permanent and cannot be undone. All your data will be removed in accordance with our privacy policy.',
        category: 'Account',
        order: 19,
      ),
    ];
  }
}
