// lib/features/documentation/data/docs/booking_docs/time_slots_explained.dart
import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';


class TimeSlotsExplainedDocs implements DocumentationModule {
  @override
  int get order => 5;

  @override
  String getTitle(BuildContext context) => 'Understanding Time Slots';

  @override
  String get id => 'timeSlotsExplained';

  @override
  String getSubtitle(BuildContext context) =>
      'Regular vs Combined View – and when to use each';

  @override
  IconData get icon => Icons.access_time;

  @override
  List<ManualSection> getSections(BuildContext context) => [
        ManualSection(
          id: 'time_intro',
          title: 'Why Two Views?',
          subtitle: 'Giving you more control over your booking',
          icon: Icons.visibility,
          category: 'Time Slots',
          order: 1,
          contents: [
            ManualContent(
              id: 'time_intro_text',
              title: 'Two Ways to See Available Times',
              content:
                  'When you select a date for your booking, you\'ll see available time slots. But did you notice you can switch between two different views? Regular View and Combined View show you the same slots in different ways, each useful for different situations.',
              numberPrefix: '1',
              type: ManualContentType.text,
            ),
            ManualContent(
              id: 'time_switch',
              title: 'How to Switch Views',
              content:
                  'Look for the toggle switch at the top of the time slot screen. It usually says "Show Combined Slots". Tap it to switch between views. The toggle only appears when you have multiple services selected.',
              type: ManualContentType.text,
            ),
            ManualContent(
              id: 'time_important',
              title: '',
              content:
                  'The toggle switch only appears when you have selected more than one service. For single services, both views would show the same thing, so we keep it simple!',
              type: ManualContentType.important,
            ),
          ],
        ),
        ManualSection(
          id: 'regular_view',
          title: 'Regular View',
          subtitle: 'See slots for each service separately',
          icon: Icons.view_list,
          category: 'Time Slots',
          order: 2,
          contents: [
            ManualContent(
              id: 'regular_explained',
              title: 'What is Regular View?',
              content:
                  'Regular View shows you available time slots for each service **independently**. You\'ll see separate lists of slots for each service you\'ve selected.',
              numberPrefix: '1',
              type: ManualContentType.text,
            ),
            ManualContent(
              id: 'regular_example',
              title: 'Example: Regular View with 2 Services',
              content:
                  '**You\'ve selected:**\n'
                  '• Haircut (1 hour)\n'
                  '• Beard Trim (30 minutes)\n\n'
                  '**Regular View shows:**\n'
                  '━━━━━━━━━━━━━━━━━━━━━━━\n'
                  '**HAIRCUT SLOTS**\n'
                  '• 9:00 AM - 10:00 AM\n'
                  '• 9:30 AM - 10:30 AM\n'
                  '• 10:00 AM - 11:00 AM\n'
                  '• 10:30 AM - 11:30 AM\n\n'
                  '**BEARD TRIM SLOTS**\n'
                  '• 9:00 AM - 9:30 AM\n'
                  '• 9:30 AM - 10:00 AM\n'
                  '• 10:00 AM - 10:30 AM\n'
                  '• 10:30 AM - 11:00 AM',
              type: ManualContentType.text,
            ),
            ManualContent(
              id: 'regular_when',
              title: 'When to Use Regular View',
              content:
                  'Regular View is most useful when:',
              numberPrefix: '2',
              type: ManualContentType.bulletList,
              bulletPoints: [
                '**You haven\'t decided on timing yet** – See all possibilities',
                '**You want flexibility** – Mix and match different times',
                '**You\'re still choosing workers** – See availability per service',
                '**Services have very different durations** – Compare options',
              ],
            ),
            ManualContent(
              id: 'regular_challenge',
              title: 'The Challenge with Regular View',
              content:
                  'The challenge with Regular View is that you have to find a time that works for ALL your services. For example, you might pick:\n'
                  '• Haircut at 9:00 AM\n'
                  '• Beard Trim at 9:30 AM\n\n'
                  '**Problem:** These overlap! You can\'t be in two places at once.',
              type: ManualContentType.warning,
            ),
            ManualContent(
              id: 'regular_tip',
              title: '',
              content:
                  'Use Regular View to explore possibilities, then switch to Combined View to find times that actually work together.',
              type: ManualContentType.tip,
            ),
          ],
        ),
        ManualSection(
          id: 'combined_view',
          title: 'Combined View',
          subtitle: 'See only slots where ALL services fit together',
          icon: Icons.merge_type,
          category: 'Time Slots',
          order: 3,
          contents: [
            ManualContent(
              id: 'combined_explained',
              title: 'What is Combined View?',
              content:
                  'Combined View does the hard work for you. It shows only time slots where **ALL your selected services can be booked together** in one continuous appointment.',
              numberPrefix: '1',
              type: ManualContentType.text,
            ),
            ManualContent(
              id: 'combined_example',
              title: 'Example: Combined View with 2 Services',
              content:
                  '**Same services:** Haircut (1 hour) + Beard Trim (30 min)\n\n'
                  '**Combined View shows:**\n'
                  '━━━━━━━━━━━━━━━━━━━━━━━\n'
                  '• 9:00 AM - 10:30 AM (both services)\n'
                  '• 9:30 AM - 11:00 AM (both services)\n'
                  '• 10:00 AM - 11:30 AM (both services)\n'
                  '• 10:30 AM - 12:00 PM (both services)\n\n'
                  '**Notice:** Each slot is LONGER because it includes BOTH services back-to-back.',
              type: ManualContentType.text,
            ),
            ManualContent(
              id: 'combined_calculation',
              title: 'How Combined Duration is Calculated',
              content:
                  'The system adds up:',
              numberPrefix: '2',
              type: ManualContentType.bulletList,
              bulletPoints: [
                '**Service 1 duration** (e.g., 60 min)',
                '**+ Service 2 duration** (e.g., 30 min)',
                '**+ Buffer time** between services (5-10 min for cleanup)',
                '**= Total appointment time** (e.g., 95-100 min)',
              ],
            ),
            ManualContent(
              id: 'combined_example_calc',
              title: 'Example Calculation',
              content:
                  '**Haircut (60 min) + Beard Trim (30 min) + Buffer (5 min):**\n'
                  '• Start: 9:00 AM\n'
                  '• Haircut: 9:00 - 10:00\n'
                  '• Buffer: 10:00 - 10:05 (cleanup)\n'
                  '• Beard Trim: 10:05 - 10:35\n'
                  '• **End: 10:35 AM**\n'
                  '• Slot shown: 9:00 AM - 10:35 AM',
              type: ManualContentType.text,
            ),
            ManualContent(
              id: 'combined_when',
              title: 'When to Use Combined View',
              content:
                  'Combined View is perfect when:',
              numberPrefix: '3',
              type: ManualContentType.bulletList,
              bulletPoints: [
                '**You\'re ready to book** – See only realistic options',
                '**You have multiple services** – Let the system coordinate',
                '**You want simplicity** – One slot, one time, all services',
                '**You\'re booking for a group** – Ensure everyone is accommodated',
              ],
            ),
            ManualContent(
              id: 'combined_benefit',
              title: 'The Big Benefit',
              content:
                  'With Combined View, you **cannot** accidentally pick overlapping times. Every slot shown guarantees that all your services can be done in that block without conflicts.',
              type: ManualContentType.important,
            ),
          ],
        ),
        ManualSection(
          id: 'comparison',
          title: 'Regular vs Combined – Side by Side',
          subtitle: 'See the difference clearly',
          icon: Icons.compare_arrows,
          category: 'Time Slots',
          order: 4,
          contents: [
            ManualContent(
              id: 'comparison_table',
              title: 'Quick Comparison',
              content:
                  '| Feature | Regular View | Combined View |\n'
                  '|---------|--------------|---------------|\n'
                  '| **Shows** | Slots per service | Slots for all services together |\n'
                  '| **Duration** | Individual service time | Total time for all services |\n'
                  '| **Risk of overlap** | High – you must check | None – guaranteed to work |\n'
                  '| **Best for** | Exploring options | Confirming booking |\n'
                  '| **When to use** | Early in planning | Ready to book |',
              type: ManualContentType.text,
            ),
            ManualContent(
              id: 'comparison_visual',
              title: 'Visual Example – 2 Services',
              content:
                  '**REGULAR VIEW:**\n'
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
                  'Haircut:    9:00┄┄10:00   9:30┄┄10:30   10:00┄┄11:00\n'
                  'Beard Trim: 9:00┄┄9:30    9:30┄┄10:00   10:00┄┄10:30\n\n'
                  '**COMBINED VIEW:**\n'
                  '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
                  'Both:       9:00┄┄┄┄┄┄┄┄┄┄10:30\n'
                  '            9:30┄┄┄┄┄┄┄┄┄┄11:00\n'
                  '            10:00┄┄┄┄┄┄┄┄┄11:30',
              type: ManualContentType.text,
            ),
            ManualContent(
              id: 'comparison_example',
              title: 'Real Booking Example',
              content:
                  '**Sarah wants to book Haircut + Beard Trim for her son.**\n\n'
                  'Using **Regular View**, she might pick:\n'
                  '• Haircut at 9:30 AM\n'
                  '• Beard Trim at 10:00 AM\n'
                  '❌ These overlap! The worker can\'t do both.\n\n'
                  'Using **Combined View**, she sees:\n'
                  '• 9:30 AM - 10:35 AM ✅ Works perfectly\n'
                  '• 10:00 AM - 11:05 AM ✅ Also works\n\n'
                  'Combined View saves her from making a mistake!',
              type: ManualContentType.text,
            ),
          ],
        ),
        ManualSection(
          id: 'group_time',
          title: 'Time Slots for Group Bookings',
          subtitle: 'How it works with multiple people',
          icon: Icons.group,
          category: 'Time Slots',
          order: 5,
          contents: [
            ManualContent(
              id: 'group_time_intro',
              title: 'Groups Make It More Complex',
              content:
                  'When you\'re booking for multiple people, time slot calculation becomes more interesting. The system considers:',
              numberPrefix: '1',
              type: ManualContentType.bulletList,
              bulletPoints: [
                '**Number of people** (quantity)',
                '**Service duration × quantity**',
                '**Worker assignments** (same or different workers)',
                '**Buffer times** between each person\'s service',
              ],
            ),
            ManualContent(
              id: 'group_time_same_worker',
              title: 'Example: Same Worker for Everyone',
              content:
                  '**Family of 3 booking haircuts (45 min each) with the same worker:**\n'
              '• Person 1: 9:00 - 9:45\n'
              '• Buffer: 9:45 - 9:50\n'
              '• Person 2: 9:50 - 10:35\n'
              '• Buffer: 10:35 - 10:40\n'
              '• Person 3: 10:40 - 11:25\n'
              '• **Combined slot: 9:00 AM - 11:25 AM**',
              type: ManualContentType.text,
            ),
            ManualContent(
              id: 'group_time_diff_workers',
              title: 'Example: Different Workers',
              content:
                  '**Same family, but with 3 different workers:**\n'
              '• Worker A: Person 1 (9:00 - 9:45)\n'
              '• Worker B: Person 2 (9:00 - 9:45) at same time\n'
              '• Worker C: Person 3 (9:00 - 9:45) at same time\n'
              '• **Combined slot: 9:00 AM - 9:45 AM** (much shorter!)',
              type: ManualContentType.text,
            ),
            ManualContent(
              id: 'group_time_combined',
              title: 'Combined View for Groups',
              content:
                  'When booking for groups, Combined View is **especially valuable**. It shows only time blocks where ALL people can be served, with the correct total duration based on your worker choices.',
              type: ManualContentType.text,
            ),
            ManualContent(
              id: 'group_time_tip',
              title: '',
              content:
                  'For large groups, choosing different workers can significantly reduce the total time needed. The system shows you the duration based on your worker selections.',
              type: ManualContentType.tip,
            ),
          ],
        ),
        ManualSection(
          id: 'buffer_time',
          title: 'Understanding Buffer Time',
          subtitle: 'Why there are gaps between appointments',
          icon: Icons.timer,
          category: 'Time Slots',
          order: 6,
          contents: [
            ManualContent(
              id: 'buffer_explained',
              title: 'What is Buffer Time?',
              content:
                  'Buffer time is a short gap (usually 5-15 minutes) between appointments. You won\'t see it in the slot times, but it\'s there behind the scenes.',
              numberPrefix: '1',
              type: ManualContentType.text,
            ),
            ManualContent(
              id: 'buffer_purpose',
              title: 'Why Buffer Time Matters',
              content:
                  'Buffer time gives workers a moment to:',
              numberPrefix: '2',
              type: ManualContentType.bulletList,
              bulletPoints: [
                '**Clean and sanitize** their workspace',
                '**Prepare tools** for the next client',
                '**Take a quick break** between appointments',
                '**Handle any unexpected delays**',
              ],
            ),
            ManualContent(
              id: 'buffer_visibility',
              title: 'Do You See Buffer Time?',
              content:
                  '**No!** Buffer time is invisible to you. The slot you see (e.g., 9:00 - 10:30) is the time you\'ll be at the shop. The system adds buffer automatically behind the scenes to ensure realistic scheduling.',
              type: ManualContentType.important,
            ),
            ManualContent(
              id: 'buffer_example',
              title: 'How Buffer Affects Availability',
              content:
                  '**Without buffer:**\n'
                  '• 9:00 - 10:00 (Service A)\n'
                  '• 10:00 - 11:00 (Service B) – No time to clean!\n\n'
                  '**With 5-min buffer (invisible to you):**\n'
                  '• 9:00 - 10:00 (Service A) – actually ends at 10:05\n'
                  '• 10:05 - 11:05 (Service B) – starts after cleanup\n\n'
                  'You still see "9:00 - 10:00" and "10:05 - 11:05" as your appointment times.',
              type: ManualContentType.text,
            ),
            ManualContent(
              id: 'buffer_fairness',
              title: '',
              content:
                  'Buffer time ensures workers aren\'t rushed and you get their full attention. It\'s a win-win for everyone!',
              type: ManualContentType.tip,
            ),
          ],
        ),
        ManualSection(
          id: 'time_faq',
          title: 'Common Time Slot Questions',
          subtitle: 'Quick answers to frequent questions',
          icon: Icons.help,
          category: 'Time Slots',
          order: 7,
          contents: [
            ManualContent(
              id: 'time_faq_1',
              title: 'Why are some times not available?',
              content:
                  'Times may be unavailable because:\n'
                  '• The worker is already booked\n'
                  '• The shop is closed (check opening hours)\n'
                  '• There\'s not enough time before closing\n'
                  '• The worker has marked themselves unavailable (vacation, break)',
              type: ManualContentType.text,
            ),
            ManualContent(
              id: 'time_faq_2',
              title: 'Why do slots start at odd times like 9:05?',
              content:
                  'Slots may start at unusual times because of buffer periods. For example, if a 9:00 appointment ends at 10:05 (including buffer), the next slot starts at 10:05.',
              type: ManualContentType.text,
            ),
            ManualContent(
              id: 'time_faq_3',
              title: 'Can I book a slot that\'s shorter than shown?',
              content:
                  'No, the slot duration shown is the minimum time needed for your services. You cannot book a shorter slot because there wouldn\'t be enough time.',
              type: ManualContentType.text,
            ),
            ManualContent(
              id: 'time_faq_4',
              title: 'What if I need more time than the slot shows?',
              content:
                  'If you need extra time (e.g., for a more complex service), contact the shop directly. They may have special arrangements.',
              type: ManualContentType.text,
            ),
          ],
        ),
      ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_time_regular_vs_combined',
        question: 'When should I use Regular vs Combined View?',
        answer:
            'Use **Regular View** when you\'re exploring options and want to see all possibilities. Switch to **Combined View** when you\'re ready to book and want to see only slots where all your services can be done together without conflicts.',
        category: 'Time Slots',
        order: 1,
      ),
      FAQModel(
        id: 'faq_time_combined_not_showing',
        question: 'Why is Combined View not showing any slots?',
        answer:
            'If Combined View shows no slots, it means there\'s no single time block where all your selected services can be done together. Try:\n'
            '• Selecting a different date\n'
            '• Reducing the number of services\n'
            '• Choosing different workers\n'
            '• Being flexible with morning/afternoon times',
        category: 'Time Slots',
        order: 2,
      ),
      FAQModel(
        id: 'faq_time_buffer',
        question: 'What is buffer time and why is it needed?',
        answer:
            'Buffer time is a short gap (5-15 minutes) between appointments that allows workers to clean their workspace, prepare tools, and take brief breaks. It ensures quality service and a clean environment for every client. You won\'t see it in your appointment time, but it\'s built into the schedule.',
        category: 'Time Slots',
        order: 3,
      ),
      FAQModel(
        id: 'faq_time_duration',
        question: 'How is the total duration calculated?',
        answer:
            'For multiple services, the system adds:\n'
            '• Duration of Service A\n'
            '• Duration of Service B (and so on)\n'
            '• Buffer time between each service\n'
            'The result is your total appointment time.',
        category: 'Time Slots',
        order: 4,
      ),
      FAQModel(
        id: 'faq_time_group',
        question: 'How does time work for group bookings?',
        answer:
            'For groups, total time = (service duration × number of people) + buffer times between people. If you choose different workers who can work in parallel, the total time may be much shorter.',
        category: 'Time Slots',
        order: 5,
      ),
      FAQModel(
        id: 'faq_time_am_pm',
        question: 'Are times shown in my local time?',
        answer:
            'Yes! All times shown in the app are automatically converted to your device\'s local timezone. You don\'t need to worry about timezone conversions.',
        category: 'Time Slots',
        order: 6,
      ),
      FAQModel(
        id: 'faq_time_last_slot',
        question: 'Why can\'t I book the last slot of the day?',
        answer:
            'The last slot must end before the shop closes, including buffer time. If a service takes 1 hour with 5 min buffer, the last possible start time is 55 minutes before closing.',
        category: 'Time Slots',
        order: 7,
      ),
      FAQModel(
        id: 'faq_time_change',
        question: 'Can I change my time after booking?',
        answer:
            'Yes, you can reschedule up to 24 hours before your appointment. Go to "My Bookings", find your booking, and tap "Reschedule". Available times will be shown.',
        category: 'Time Slots',
        order: 8,
      ),
      FAQModel(
        id: 'faq_time_slot_not_appearing',
        question: 'A slot I wanted disappeared – what happened?',
        answer:
            'Someone else may have booked it while you were deciding. Slots are reserved only after payment is complete. Try a different time or date.',
        category: 'Time Slots',
        order: 9,
      ),
      FAQModel(
        id: 'faq_time_workers',
        question: 'Does the time change if I choose a different worker?',
        answer:
            'Yes, different workers may have different availability. If you change workers, the system will show times when that worker is free. You may need to adjust your time.',
        category: 'Time Slots',
        order: 10,
      ),
    ];
  }
}
