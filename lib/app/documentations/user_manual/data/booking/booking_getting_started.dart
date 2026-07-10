// lib/features/documentation/data/docs/booking_docs/booking_getting_started.dart

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class BookingGettingStartedDocs implements DocumentationModule {
  @override
  int get order => 1;

  @override
  String getTitle(BuildContext context) => 'Getting Started with Bookings';

  @override
  String get id => 'bookingGettingStarted';

  @override
  String getSubtitle(BuildContext context) =>
      'A simple guide to understanding how bookings work';

  @override
  IconData get icon => Icons.calendar_month;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'booking_introduction',
      title: 'Welcome to the Booking System',
      subtitle:
          'Everything you need to know about booking services, whether you\'re a client or a shop owner.',
      icon: Icons.auto_awesome,
      category: 'Booking Guide',
      order: 1,
      contents: [
        ManualContent(
          id: 'what_is_booking',
          title: 'What is the Booking System?',
          content:
              'The booking system is your gateway to scheduling services at your favorite shops. Whether you need a haircut, beard trim, braiding, or any other service, the system makes it easy to book appointments at your convenience.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'who_its_for',
          title: 'Who is this guide for?',
          content: 'This guide is designed for two types of users:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Clients:** People who want to book services at shops',
            '**Shop Owners:** People who manage shops, services, and workers',
          ],
        ),
        ManualContent(
          id: 'welcome_note',
          title: '',
          content:
              'No technical knowledge needed! This guide uses simple language and real examples to help you understand everything.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'creating_account',
      title: 'Creating Your Account',
      subtitle: 'Get started in minutes',
      icon: Icons.person_add,
      category: 'Getting Started',
      order: 2,
      contents: [
        ManualContent(
          id: 'account_steps',
          title: 'How to create an account',
          content: 'Follow these simple steps to create your account:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Download the app from App Store or Google Play',
            'Tap "Sign Up" on the welcome screen',
            'Enter your email address and create a password',
            'Add your name and profile picture (optional)',
            'Verify your email address',
            'You\'re ready to start booking!',
          ],
        ),
        ManualContent(
          id: 'account_types',
          title: 'Account Types',
          content: 'There are two types of accounts:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Client Account:** For booking services at shops',
            '**Shop Owner Account:** For managing your own shop (requires approval)',
          ],
        ),
        ManualContent(
          id: 'verification_note',
          title: '',
          content:
              'You can browse shops and services without an account, but you\'ll need to sign in to actually book appointments.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'first_booking',
      title: 'Your First Booking',
      subtitle: 'A quick walkthrough',
      icon: Icons.event_available,
      category: 'Getting Started',
      order: 3,
      contents: [
        ManualContent(
          id: 'booking_steps',
          title: 'How to make your first booking',
          content: 'Here\'s what you\'ll do:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Find a shop you like',
            'Browse their services',
            'Select the services you want',
            'Choose your preferred worker (if available)',
            'Pick a date and time',
            'Review and confirm your booking',
          ],
        ),
        ManualContent(
          id: 'what_happens_next',
          title: 'What happens after you book?',
          content: 'Once you confirm your booking:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'You\'ll get an instant confirmation',
            'The booking appears in "My Bookings"',
            'You\'ll receive a reminder before your appointment',
            'The shop gets notified of your booking',
            'You can reschedule or cancel if plans change',
          ],
        ),
        ManualContent(
          id: 'payment_process',
          title: 'How Payment Works',
          content: 'When you book a service, here\'s how payment works:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**30% Deposit Required:** To secure your booking, you pay 30% of the total service cost upfront',
            '**Non-Refundable:** This deposit is non-refundable if you cancel or don\'t show up',
            '**Remaining Balance:** The remaining 70% is paid after your service is completed',
            '**Secure Payment:** All payments are processed securely through our payment partners',
          ],
        ),

        ManualContent(
          id: 'deposit_note',
          title: '',
          content:
              'The 30% deposit protects both you and the shop. It ensures your slot is reserved exclusively for you, and compensates the worker if you cancel last minute.',
          type: ManualContentType.important,
        ),
        ManualContent(
          id: 'booking_tip',
          title: '',
          content:
              'Pro tip: Book at least 24 hours in advance for the best selection of time slots, especially for popular services.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'navigation',
      title: 'Finding Your Way Around',
      subtitle: 'Key screens and what they do',
      icon: Icons.map,
      category: 'Getting Started',
      order: 4,
      contents: [
        ManualContent(
          id: 'main_screens',
          title: 'Main Screens',
          content: 'The app has several key screens to help you navigate:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Home:** Discover shops and services near you',
            '**Search:** Find specific shops or services',
            '**My Bookings:** View and manage your appointments',
            '**Profile:** Your account settings and preferences',
            '**Favorites:** Save shops you love for quick access',
          ],
        ),
        ManualContent(
          id: 'booking_flow',
          title: 'The Booking Flow',
          content: 'When you start booking, you\'ll go through these steps:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Services:** Choose what you want',
            '**Workers:** Pick who you want (if applicable)',
            '**Time:** Select your preferred date and time',
            '**Confirm:** Review and finalize your booking',
          ],
        ),
        ManualContent(
          id: 'navigation_tip',
          title: '',
          content:
              'You can always go back to previous steps using the back button. Your selections are saved as you move through the flow.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'booking_basics',
      title: 'Booking Basics',
      subtitle: 'Key concepts explained simply',
      icon: Icons.school,
      category: 'Getting Started',
      order: 5,
      contents: [
        ManualContent(
          id: 'key_concepts',
          title: 'Important Terms to Know',
          content: 'Here are some terms you\'ll encounter:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Service:** What you want done (haircut, braids, etc.)',
            '**Worker:** The person who performs the service',
            '**Slot:** A specific date and time for your appointment',
            '**Group Booking:** Booking for multiple people at once',
            '**Buffer Time:** Clean-up time between appointments (you won\'t see this)',
          ],
        ),
        ManualContent(
          id: 'what_you_need',
          title: 'What You Need Before Booking',
          content: 'Before you start, have this information ready:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'The service you want',
            'Preferred date and time (flexibility helps!)',
            'Number of people (if booking for a group)',
            'Worker preference (if you have one)',
          ],
        ),
        ManualContent(
          id: 'deposit_explained',
          title: 'Understanding the Deposit',
          content: 'Here\'s a real example of how the deposit works:',
          numberPrefix: '3',
          type: ManualContentType.text,
        ),

        ManualContent(
          id: 'deposit_example',
          title: 'Example',
          content:
              '**Sarah books a haircut that costs GHS 100.**\n'
              '• At booking: She pays GHS 30 (30% deposit)\n'
              '• After service: She pays GHS 70 (remaining balance)\n'
              '• Total paid: GHS 100\n\n'
              '**If Sarah cancels:** She loses the GHS 30 deposit, but isn\'t charged the remaining GHS 70.\n\n'
              '**If Sarah doesn\'t show up:** Same as cancellation - the GHS 30 deposit is kept.',
          type: ManualContentType.text,
        ),

        ManualContent(
          id: 'deposit_tip',
          title: '',
          content:
              'The deposit is applied toward your total bill. You\'re not paying extra - you\'re just paying part of it upfront to secure your spot.',
          type: ManualContentType.tip,
        ),

        ManualContent(
          id: 'basics_important',
          title: '',
          content:
              'All times shown in the app are in your local timezone. No need to worry about timezone conversions!',
          type: ManualContentType.important,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_gs_no_account',
        question: 'Can I book without an account?',
        answer:
            'You can browse shops and services without an account, but you\'ll need to sign up to actually book appointments. This helps us keep track of your bookings and send you reminders.',
        category: 'Getting Started',
        order: 1,
      ),
      FAQModel(
        id: 'faq_gs_cost',
        question: 'Does it cost anything to use the booking system?',
        answer:
            'The booking system is completely free for clients. You only pay for the services you book. Shop owners pay a small commission on each booking.',
        category: 'Getting Started',
        order: 2,
      ),
      FAQModel(
        id: 'faq_gs_multiple_shops',
        question: 'Can I book at multiple shops at the same time?',
        answer:
            'Yes! You can book appointments at different shops. Just make sure the times don\'t overlap if you\'re planning to attend them all yourself.',
        category: 'Getting Started',
        order: 3,
      ),
      FAQModel(
        id: 'faq_gs_deposit_refund',
        question: 'Is the deposit refundable if I cancel?',
        answer:
            'No, the 30% deposit is non-refundable. This policy helps shops protect their time in case of last-minute cancellations or no-shows. You can cancel up to 24 hours before your appointment to avoid being charged the remaining 70%, but the deposit will not be refunded.',
        category: 'Getting Started',
        order: 8,
      ),

      FAQModel(
        id: 'faq_gs_deposit_amount',
        question: 'Why 30%? Why not a fixed amount?',
        answer:
            'The 30% deposit scales with the cost of your service. For expensive services, the deposit is higher (protecting the shop more), and for cheaper services, it\'s lower (fairer for you). This percentage was chosen as a balanced approach that works for both clients and shops.',
        category: 'Getting Started',
        order: 9,
      ),

      FAQModel(
        id: 'faq_gs_deposit_multiple',
        question: 'If I book multiple services, do I pay 30% of the total?',
        answer:
            'Yes! The 30% deposit is calculated based on the total cost of all services you\'re booking. So if your total is GHS 200, you\'ll pay GHS 60 upfront, and the remaining GHS 140 after your appointment.',
        category: 'Getting Started',
        order: 10,
      ),

      FAQModel(
        id: 'faq_gs_deposit_emergency',
        question: 'What if I have a genuine emergency?',
        answer:
            'We understand that emergencies happen. While the deposit is officially non-refundable, you can contact the shop directly through the app to explain your situation. Some shops may offer credit toward a future booking at their discretion.',
        category: 'Getting Started',
        order: 11,
      ),
      FAQModel(
        id: 'faq_gs_reminders',
        question: 'Will I get reminders about my booking?',
        answer:
            'Yes! You\'ll receive reminders 24 hours before your appointment and again 1 hour before. You can adjust reminder settings in your profile.',
        category: 'Getting Started',
        order: 5,
      ),
      FAQModel(
        id: 'faq_gs_payment',
        question: 'When do I pay for my booking?',
        answer:
            'Payment is handled at the time of booking. You can pay using credit card, debit card, or other payment methods available in your region.',
        category: 'Getting Started',
        order: 6,
      ),
      FAQModel(
        id: 'faq_gs_shop_owner',
        question: 'I own a shop. How do I get started?',
        answer:
            'Great! Create an account and select "Shop Owner" during signup. You\'ll need to provide some information about your shop and wait for approval. Once approved, you can start adding services and workers.',
        category: 'Getting Started',
        order: 7,
      ),
    ];
  }
}
