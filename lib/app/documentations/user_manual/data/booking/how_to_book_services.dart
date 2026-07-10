// lib/features/documentation/data/docs/booking_docs/how_to_book_services.dart
import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class HowToBookServicesDocs implements DocumentationModule {
  @override
  int get order => 2;

  @override
  String getTitle(BuildContext context) => 'How to Book Services';

  @override
  String get id => 'howToBookServices';

  @override
  String getSubtitle(BuildContext context) =>
      'A step-by-step guide to booking your appointments';

  @override
  IconData get icon => Icons.event_note;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'booking_overview',
      title: 'Booking at a Glance',
      subtitle: 'The booking process in 5 simple steps',
      icon: Icons.timeline,
      category: 'Booking Guide',
      order: 1,
      contents: [
        ManualContent(
          id: 'booking_steps_overview',
          title: 'Your Booking Journey',
          content:
              'Booking a service takes just a few minutes. Here\'s what you\'ll do:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Step 1:** Find a shop and browse services',
            '**Step 2:** Select your services and quantities',
            '**Step 3:** Choose your preferred worker (if available)',
            '**Step 4:** Pick a date and time',
            '**Step 5:** Pay 30% deposit + small processing fee to confirm',
            '**Step 6:** After service, pay remaining 70% in cash or via app',
          ],
        ),
        ManualContent(
          id: 'booking_time_note',
          title: '',
          content:
              'The entire process usually takes less than 2 minutes. Your progress is saved as you go, so you can take your time.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'step_one',
      title: 'Step 1: Find Your Shop & Services',
      subtitle: 'Discover the perfect place for your needs',
      icon: Icons.search,
      category: 'Booking Steps',
      order: 2,
      contents: [
        ManualContent(
          id: 'find_shop',
          title: 'How to find a shop',
          content: 'You can find shops in several ways:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Home Screen:** Browse recommended shops near you',
            '**Search:** Look for specific shops or services by name',
            '**Categories:** Filter by service type (Haircut, Braiding, Beard, etc.)',
            '**Favorites:** Quick access to shops you\'ve saved',
          ],
        ),
        ManualContent(
          id: 'browse_services',
          title: 'Browsing Services',
          content:
              'Once you select a shop, you\'ll see all their available services. Each service shows:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Service name** (e.g., "Afro Haircut", "Box Braids")',
            '**Duration** (how long it takes)',
            '**Price** (cost of the service - this goes to the shop)',
            '**Description** (what\'s included)',
            '**Worker requirement** (whether you can choose who does it)',
          ],
        ),
        ManualContent(
          id: 'service_example',
          title: 'Example',
          content:
              '**Haircut Service:**\n'
              '• Name: Afro Haircut\n'
              '• Duration: 1 hour\n'
              '• Price: GHS 45 (paid to shop)\n'
              '• Description: Professional afro haircut with styling\n'
              '• Worker: You can choose your preferred barber',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'step_two',
      title: 'Step 2: Select Your Services',
      subtitle: 'Choose what you want and how many people',
      icon: Icons.checklist,
      category: 'Booking Steps',
      order: 3,
      contents: [
        ManualContent(
          id: 'select_services',
          title: 'Selecting Services',
          content:
              'To select a service, simply tap on it. You\'ll see it become highlighted. You can select multiple services at once:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Tap a service to select it',
            'Selected services show a checkmark',
            'You can select multiple services (e.g., Haircut + Beard Trim)',
            'Tap again to deselect',
          ],
        ),
        ManualContent(
          id: 'group_booking',
          title: 'Booking for Multiple People',
          content:
              'If you\'re booking for a group (like yourself and your children), you can increase the quantity:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'After selecting a service, you\'ll see a **+** and **-** button',
            'Tap **+** to increase the number of people',
            'The price updates automatically',
            'Maximum quantity is shown (some services have limits)',
          ],
        ),
        ManualContent(
          id: 'group_example',
          title: 'Example: Family Booking',
          content:
              '**Dad wants haircuts for himself and his two sons:**\n'
              '• Select "Haircut" service\n'
              '• Tap **+** until quantity shows 3\n'
              '• Total price shows 3 × GHS 45 = GHS 135 (for the shop)\n'
              '• You\'ll choose workers for each person later',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'quantity_tip',
          title: '',
          content:
              'The quantity feature is perfect for families, groups of friends, or anyone booking for multiple people at once.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'step_three',
      title: 'Step 3: Choose Your Workers',
      subtitle: 'Pick who will perform your services',
      icon: Icons.people,
      category: 'Booking Steps',
      order: 4,
      contents: [
        ManualContent(
          id: 'worker_selection',
          title: 'When You Can Choose a Worker',
          content:
              'Some services let you choose your preferred worker, while others assign whoever is available:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Services with worker choice:** You\'ll see a "Choose Worker" button',
            '**Services without worker choice:** The system will assign an available worker',
            '**Group bookings:** You can choose different workers for each person',
          ],
        ),
        ManualContent(
          id: 'choosing_worker',
          title: 'How to Choose a Worker',
          content: 'If a service lets you choose a worker:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Tap "Choose Worker" for that service',
            'You\'ll see a list of available workers',
            'Each worker shows their name, photo, specialties, and rating',
            'Tap on a worker to select them',
            'For group bookings, you\'ll choose a worker for each person',
          ],
        ),
        ManualContent(
          id: 'worker_example',
          title: 'Example: Group with Different Workers',
          content:
              '**Family of 3 booking haircuts:**\n'
              '• Person 1 (Dad): Choose John (fade specialist)\n'
              '• Person 2 (Son 1): Choose Michael (kids cuts)\n'
              '• Person 3 (Son 2): Choose Michael (same worker)\n'
              '• All three will be served during your appointment time',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'worker_tip',
          title: '',
          content:
              'You can see each worker\'s availability in real-time. If your preferred worker isn\'t available at your desired time, you\'ll need to choose a different time or worker.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'step_four',
      title: 'Step 4: Pick Your Date & Time',
      subtitle: 'Select when you want your appointment',
      icon: Icons.calendar_today,
      category: 'Booking Steps',
      order: 5,
      contents: [
        ManualContent(
          id: 'date_selection',
          title: 'Choosing a Date',
          content: 'First, pick your preferred date from the calendar:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Dates with available slots are highlighted',
            'Past dates are greyed out',
            'Today is marked with "Today"',
            'You can scroll forward up to 30 days',
          ],
        ),
        ManualContent(
          id: 'time_selection',
          title: 'Two Ways to View Time Slots',
          content:
              'Once you pick a date, you\'ll see available time slots. You can switch between two views:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Regular View:** Shows slots for each service separately',
            '**Combined View:** Shows only slots where ALL your services can be booked together',
          ],
        ),
        ManualContent(
          id: 'regular_vs_combined',
          title: 'Regular vs Combined View',
          content:
              '**Regular View Example (2 services):**\n'
              '• Haircut: 9:00 AM, 9:30 AM, 10:00 AM...\n'
              '• Beard Trim: 9:00 AM, 9:30 AM, 10:00 AM...\n\n'
              '**Combined View Example (same 2 services):**\n'
              '• 9:00 AM - 10:30 AM (both services together)\n'
              '• 9:30 AM - 11:00 AM\n'
              '• 10:00 AM - 11:30 AM',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'view_switch',
          title: '',
          content:
              'Use the toggle switch to switch between Regular and Combined view. Combined view is especially useful when booking multiple services.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'step_five',
      title: 'Step 5: Payment & Confirmation',
      subtitle: 'Secure your booking with a 30% deposit',
      icon: Icons.payment,
      category: 'Booking Steps',
      order: 6,
      contents: [
        ManualContent(
          id: 'payment_overview',
          title: 'How Payment Works',
          content:
              'To secure your booking, you\'ll pay a 30% deposit plus a small processing fee. Here\'s what you need to know:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**30% Deposit:** Required at the time of booking (goes to the shop)',
            '**Processing Fee:** Small fixed fee charged by the platform (e.g., GHS 2 per booking)',
            '**Non-Refundable Deposit:** The 30% deposit is not refunded if you cancel or don\'t show up',
            '**Processing Fee Non-Refundable:** The platform fee is also non-refundable',
            '**Secure Processing:** All payments are encrypted and secure',
          ],
        ),
        ManualContent(
          id: 'payment_example',
          title: 'Payment Example',
          content:
              '**Sarah books services totaling GHS 200:**\n'
              '• At booking: Pays GHS 60 (30% deposit for shop) + GHS 2 (platform fee) = GHS 62\n'
              '• After service: Pays remaining GHS 140 to the shop (in cash or via app)\n'
              '• Total paid: GHS 200 to shop + GHS 2 platform fee\n\n'
              '**If Sarah cancels:** She loses the GHS 60 deposit and GHS 2 fee\n'
              '**If Sarah doesn\'t show up:** Same as cancellation',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'payment_step',
          title: 'The Payment Screen',
          content: 'On the confirmation screen, you\'ll see:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Summary:** All services, quantities, and workers',
            '**Total Price:** Full cost of all services (for the shop)',
            '**Deposit Amount:** 30% payable now',
            '**Platform Fee:** Small processing fee (e.g., GHS 2)',
            '**Total Due Now:** Deposit + platform fee',
            '**Remaining Balance:** 70% to pay after service (cash or app)',
            '**Payment Methods:** Choose how to pay the deposit',
          ],
        ),
        ManualContent(
          id: 'fee_explanation',
          title: 'Understanding the Platform Fee',
          content:
              'The processing fee (e.g., GHS 2 per booking) is charged by the platform, not the shop. This fee helps us maintain the app and provide you with a great booking experience. The fee is:',
          numberPrefix: '3',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Fixed amount** (not a percentage)',
            '**Charged once per booking** (not per service)',
            '**Non-refundable** even if you cancel',
            '**Clearly shown** before you confirm',
          ],
        ),
        ManualContent(
          id: 'payment_important',
          title: '',
          content:
              'The 30% deposit goes to the shop and is applied toward your total bill. The platform fee is separate and helps keep the app running. You\'re not paying extra to the shop - just paying part of your bill upfront.',
          type: ManualContentType.important,
        ),
        ManualContent(
          id: 'remaining_payment',
          title: 'Paying the Remaining 70%',
          content:
              'After your service is complete, you have two options to pay the remaining balance:',
          numberPrefix: '4',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Cash:** Pay the worker or shop directly',
            '**Via App:** Pay through the app using your preferred payment method',
            '**Receipt:** You\'ll get a receipt regardless of how you pay',
          ],
        ),
        ManualContent(
          id: 'confirmation',
          title: 'After Payment',
          content: 'Once your deposit payment is successful:',
          numberPrefix: '5',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'You\'ll see a confirmation screen',
            'The booking appears in "My Bookings"',
            'You\'ll receive an email confirmation',
            'The shop is notified of your booking',
            'You\'ll get a reminder before your appointment',
          ],
        ),
        ManualContent(
          id: 'payment_warning',
          title: '',
          content:
              'The 30% deposit and platform fee are non-refundable. Please be sure about your booking before confirming. You can reschedule up to 24 hours before, but the deposit and fee remain non-refundable.',
          type: ManualContentType.warning,
        ),
      ],
    ),
    ManualSection(
      id: 'after_booking',
      title: 'After You Book',
      subtitle: 'What happens next',
      icon: Icons.done_all,
      category: 'Booking Guide',
      order: 7,
      contents: [
        ManualContent(
          id: 'whats_next',
          title: 'Your Booking is Confirmed!',
          content: 'Here\'s what you can do after booking:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**View Booking:** Check details in "My Bookings"',
            '**Reschedule:** Change the time (up to 24 hours before)',
            '**Cancel:** Cancel if needed (deposit and fee are non-refundable)',
            '**Contact Shop:** Message the shop directly',
            '**Add to Calendar:** Export to your phone\'s calendar',
          ],
        ),
        ManualContent(
          id: 'reminders',
          title: 'Booking Reminders',
          content: 'You\'ll receive reminders at:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**24 hours before:** Check you\'re still coming',
            '**1 hour before:** Time to head to the shop',
            '**After appointment:** Option to leave a review and pay remaining balance',
          ],
        ),
        ManualContent(
          id: 'after_service',
          title: 'After Your Service',
          content: 'Once your service is complete:',
          numberPrefix: '3',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Pay Remaining 70%:** In cash or through the app',
            '**Rate Your Experience:** Leave a review for the shop and worker',
            '**Tip Your Worker:** Optional tip can be added',
            '**Book Again:** Easily rebook with the same shop or worker',
          ],
        ),
        ManualContent(
          id: 'after_tip',
          title: '',
          content:
              'Arrive 5-10 minutes before your appointment time to check in. This gives you time to settle in before your service starts.',
          type: ManualContentType.tip,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_book_cancel',
        question: 'How do I cancel a booking?',
        answer:
            'Go to "My Bookings", find the booking, and tap "Cancel". You can cancel up to 24 hours before the appointment. The 30% deposit and platform fee are non-refundable, but you won\'t be charged the remaining 70%.',
        category: 'Booking Process',
        order: 1,
      ),
      FAQModel(
        id: 'faq_book_reschedule',
        question: 'Can I change my appointment time?',
        answer:
            'Yes! Go to "My Bookings", find your booking, and tap "Reschedule". You can choose a new time if available. The deposit and fee remain applied to your new booking.',
        category: 'Booking Process',
        order: 2,
      ),
      FAQModel(
        id: 'faq_book_deposit',
        question: 'Why do I need to pay a deposit?',
        answer:
            'The 30% deposit protects both you and the shop. It ensures your slot is reserved exclusively for you, and compensates the worker if you cancel last minute. The deposit goes toward your total bill.',
        category: 'Payment',
        order: 3,
      ),
      FAQModel(
        id: 'faq_book_platform_fee',
        question: 'What is the platform fee?',
        answer:
            'The platform fee (e.g., GHS 2 per booking) is a small fixed charge by the app, not the shop. It helps us maintain the platform and provide you with a smooth booking experience. The fee is clearly shown before you confirm.',
        category: 'Payment',
        order: 4,
      ),
      FAQModel(
        id: 'faq_book_deposit_refund',
        question: 'Is the deposit ever refundable?',
        answer:
            'The deposit and platform fee are non-refundable by policy. However, in genuine emergency situations, you can contact the shop directly through the app. Some shops may offer credit toward a future booking at their discretion, but the platform fee cannot be refunded.',
        category: 'Payment',
        order: 5,
      ),
      FAQModel(
        id: 'faq_book_remaining_payment',
        question: 'How do I pay the remaining 70%?',
        answer:
            'After your service, you have two options: pay in cash directly to the shop, or pay through the app using your preferred payment method. Both options are accepted at participating shops.',
        category: 'Payment',
        order: 6,
      ),
      FAQModel(
        id: 'faq_book_multiple_services',
        question: 'Can I book multiple services at once?',
        answer:
            'Absolutely! You can select multiple services (like haircut + beard trim) and book them together. The system will find time slots where all services can be done.',
        category: 'Booking Process',
        order: 7,
      ),
      FAQModel(
        id: 'faq_book_group',
        question: 'How do I book for multiple people?',
        answer:
            'After selecting a service, use the **+** button to increase the quantity. For example, if you\'re booking haircuts for yourself and two children, set quantity to 3. You can then choose different workers for each person.',
        category: 'Group Bookings',
        order: 8,
      ),
      FAQModel(
        id: 'faq_book_worker_change',
        question: 'Can I change my chosen worker after booking?',
        answer:
            'Yes, you can change your worker up to 24 hours before the appointment. Go to "My Bookings", find your booking, and look for the option to change worker. The new worker must be available at your booked time.',
        category: 'Workers',
        order: 9,
      ),
      FAQModel(
        id: 'faq_book_payment_methods',
        question: 'What payment methods are accepted for the deposit?',
        answer:
            'We accept various payment methods depending on your region, including credit/debit cards, mobile money, and bank transfers. Available options will be shown during checkout.',
        category: 'Payment',
        order: 10,
      ),
      FAQModel(
        id: 'faq_book_combined_view',
        question: 'When should I use Combined View?',
        answer:
            'Use Combined View when you\'ve selected multiple services. It shows only time slots where all your services can be done together, saving you from trying to coordinate separate times.',
        category: 'Time Slots',
        order: 11,
      ),
      FAQModel(
        id: 'faq_book_no_show',
        question: 'What happens if I don\'t show up?',
        answer:
            'If you don\'t show up for your appointment, the 30% deposit and platform fee are kept. You may also be marked as a "no-show". Repeated no-shows may result in restrictions on your account.',
        category: 'Booking Process',
        order: 12,
      ),
      FAQModel(
        id: 'faq_book_cash_payment',
        question: 'Can I really pay the remaining amount in cash?',
        answer:
            'Yes! Many shops accept cash for the remaining 70%. You can also choose to pay through the app if you prefer. The choice is yours at the time of service.',
        category: 'Payment',
        order: 13,
      ),
      FAQModel(
        id: 'faq_book_fee_per_booking',
        question: 'Is the platform fee charged per service or per booking?',
        answer:
            'The platform fee is charged **per booking**, not per service. So whether you book one service or multiple services together, you pay the platform fee only once.',
        category: 'Payment',
        order: 14,
      ),
    ];
  }
}
