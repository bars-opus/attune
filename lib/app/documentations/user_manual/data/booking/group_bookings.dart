// lib/features/documentation/data/docs/booking_docs/group_bookings.dart

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class GroupBookingsDocs implements DocumentationModule {
  @override
  int get order => 3;

  @override
  String getTitle(BuildContext context) => 'Group Bookings';

  @override
  String get id => 'groupBookings';

  @override
  String getSubtitle(BuildContext context) =>
      'How to book services for yourself and others';

  @override
  IconData get icon => Icons.group;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'group_intro',
      title: 'What Are Group Bookings?',
      subtitle: 'Booking for family, friends, or groups made simple',
      icon: Icons.group_add,
      category: 'Group Bookings',
      order: 1,
      contents: [
        ManualContent(
          id: 'group_explained',
          title: 'Booking for Multiple People',
          content:
              'Group bookings allow you to book services for more than one person at a time. This is perfect for:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Families:** Parents booking haircuts for themselves and their children',
            '**Friends:** Group of friends getting services together',
            '**Events:** Bridal parties, birthdays, or special occasions',
            '**Colleagues:** Team building or work outings',
          ],
        ),
        ManualContent(
          id: 'group_example',
          title: 'Real-Life Example',
          content:
              '**The Mensah Family needs haircuts:**\n'
              '• Father: Wants a fade haircut\n'
              '• Mother: Wants a trim\n'
              '• Son (10): Wants a kids haircut\n'
              '• Daughter (8): Wants braids\n\n'
              'Instead of making 4 separate bookings, they can book everything together in one go!',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'group_benefits',
          title: 'Benefits of Group Booking',
          content: 'Booking as a group gives you:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**One transaction:** Pay deposits for everyone at once',
            '**Coordinated timing:** Everyone gets served around the same time',
            '**Different workers:** Each person can choose their preferred worker',
            '**Simplified management:** View and manage all bookings together',
            '**Better planning:** Shop can prepare for your group',
          ],
        ),
        ManualContent(
          id: 'group_tip',
          title: '',
          content:
              'Group bookings are perfect for families! You can book for yourself and your children in one go, choosing different workers for each person.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'how_to_group',
      title: 'How to Make a Group Booking',
      subtitle: 'Step-by-step guide',
      icon: Icons.layers,
      category: 'Group Bookings',
      order: 2,
      contents: [
        ManualContent(
          id: 'group_step1',
          title: 'Step 1: Select Your Service',
          content:
              'Start by finding a shop and selecting the service you want. For example, tap on "Haircut".',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'group_step2',
          title: 'Step 2: Choose the Quantity',
          content:
              'After selecting a service, you\'ll see **+** and **-** buttons. Use these to set how many people need this service:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Tap **+** to increase the number',
            'Tap **-** to decrease',
            'The price updates automatically',
            'You cannot exceed the maximum quantity shown',
          ],
        ),
        ManualContent(
          id: 'group_step2_example',
          title: 'Example',
          content:
              '**For a family of 3 needing haircuts:**\n'
              '• Select "Haircut" service\n'
              '• Tap **+** twice (or until quantity shows 3)\n'
              '• Total price shows: 3 × GHS 45 = GHS 135',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'group_step3',
          title: 'Step 3: Repeat for Each Service',
          content:
              'If your group needs different services (e.g., some want haircuts, others want braids), select each service and set the quantity for each:',
          numberPrefix: '3',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Select "Haircut" → set quantity 2',
            'Select "Braids" → set quantity 1',
            'The system keeps track of all selections',
          ],
        ),
        ManualContent(
          id: 'group_step3_example',
          title: 'Example: Mixed Services',
          content:
              '**Family of 4 with different needs:**\n'
              '• Dad: Haircut (quantity 1)\n'
              '• Mom: Trim (quantity 1)\n'
              '• Son: Kids Haircut (quantity 1)\n'
              '• Daughter: Braids (quantity 1)\n\n'
              'Total: 4 services, but you booked them all in one go!',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'group_step4',
          title: 'Step 4: Choose Workers for Each Person',
          content:
              'For services that let you choose workers, you\'ll see a list of people. Tap on each person to assign their worker:',
          numberPrefix: '4',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Person 1:** Choose John (fade specialist)',
            '**Person 2:** Choose Sarah (braiding expert)',
            '**Person 3:** Choose Michael (kids cuts)',
            '**Person 4:** Choose John (same worker for multiple people)',
          ],
        ),
        ManualContent(
          id: 'group_step4_example',
          title: 'Example: Different Workers for Different People',
          content:
              '**Family of 3 booking haircuts:**\n'
              '• Person 1 (Dad): Choose John (fade specialist)\n'
              '• Person 2 (Son): Choose Michael (great with kids)\n'
              '• Person 3 (Daughter): Choose Sarah (braiding expert)\n\n'
              'All three will be served during your appointment block.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'group_step5',
          title: 'Step 5: Pick Your Time',
          content:
              'When you select a date and time, the system will show slots that can accommodate ALL people in your group:',
          numberPrefix: '5',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Regular View:** Shows slots for each service separately',
            '**Combined View:** Shows only slots where everyone can be served together',
            '**Duration:** The time shown includes all services for all people',
          ],
        ),
        ManualContent(
          id: 'group_step5_example',
          title: 'Example: Time Calculation',
          content:
              '**Family booking:**\n'
              '• Haircut (45 min) × 2 people = 90 min\n'
              '• Braids (2 hours) × 1 person = 120 min\n'
              '• Buffer time between services = 15 min\n'
              '• **Total appointment time: 3 hours 45 min**\n\n'
              'The system handles all this automatically!',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'group_step6',
          title: 'Step 6: Payment',
          content: 'For group bookings, you pay:',
          numberPrefix: '6',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**30% deposit:** Calculated on the TOTAL cost of all services',
            '**Platform fee:** One fee for the entire group booking',
            '**Remaining 70%:** Paid after all services are complete (cash or app)',
          ],
        ),
        ManualContent(
          id: 'group_step6_example',
          title: 'Payment Example',
          content:
              '**Family booking total: GHS 400**\n'
              '• Deposit at booking: GHS 120 (30% of GHS 400) + GHS 2 fee = GHS 122\n'
              '• Remaining after service: GHS 280 (pay in cash or via app)\n'
              '• Total to shop: GHS 400 + GHS 2 platform fee',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'group_important',
          title: '',
          content:
              'The deposit and platform fee are calculated on the TOTAL group booking, not per person. You pay once for the whole group.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'group_worker',
      title: 'Worker Selection for Groups',
      subtitle: 'How workers are assigned',
      icon: Icons.people,
      category: 'Group Bookings',
      order: 3,
      contents: [
        ManualContent(
          id: 'group_worker_intro',
          title: 'One Worker or Multiple Workers?',
          content:
              'When booking for a group, you have flexibility in how workers are assigned:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Same worker for everyone:** If one worker can handle everyone (sequentially)',
            '**Different workers:** Each person can have their preferred worker',
            '**Mix and match:** Some people share a worker, others have different ones',
          ],
        ),
        ManualContent(
          id: 'group_worker_same',
          title: 'Same Worker for Everyone',
          content:
              'If you choose the same worker for everyone, they will serve each person one after another. The total time is the sum of all services plus buffers.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'group_worker_different',
          title: 'Different Workers for Different People',
          content:
              'When you choose different workers, they can work in parallel. This might reduce the total time needed. Example:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Worker A:** Serves Person 1 (haircut)',
            '**Worker B:** Serves Person 2 (braids) at the same time',
            '**Worker A:** Then serves Person 3 (beard trim)',
            '**Result:** Everyone finishes faster!',
          ],
        ),
        ManualContent(
          id: 'group_worker_interface',
          title: 'How to Assign Workers',
          content:
              'In the worker selection screen, you\'ll see each person listed separately:',
          numberPrefix: '3',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'group_worker_example',
          title: 'What You\'ll See',
          content:
              '**For a group of 3 booking haircuts:**\n'
              '• **Person 1:** [Choose Worker] → John\n'
              '• **Person 2:** [Choose Worker] → Michael\n'
              '• **Person 3:** [Choose Worker] → John (again)\n\n'
              'Tap each person to select their worker from the available list.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'group_worker_tip',
          title: '',
          content:
              'If a worker is already chosen for one person, they remain available for others unless fully booked. The system shows real-time availability.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'group_time',
      title: 'Time Slots for Groups',
      subtitle: 'How appointment times work for groups',
      icon: Icons.access_time,
      category: 'Group Bookings',
      order: 4,
      contents: [
        ManualContent(
          id: 'group_time_calculation',
          title: 'How Duration is Calculated',
          content:
              'For group bookings, the total appointment time is calculated based on:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Service duration × quantity** for each service type',
            '**Buffer time** between services (for cleanup)',
            '**Parallel work** if multiple workers are assigned',
          ],
        ),
        ManualContent(
          id: 'group_time_example_sequential',
          title: 'Example: Sequential (Same Worker)',
          content:
              '**One worker doing 3 haircuts (45 min each):**\n'
              '• Haircut 1: 9:00 - 9:45\n'
              '• Buffer: 9:45 - 9:50 (5 min)\n'
              '• Haircut 2: 9:50 - 10:35\n'
              '• Buffer: 10:35 - 10:40\n'
              '• Haircut 3: 10:40 - 11:25\n'
              '• **Total: 2 hours 25 min**',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'group_time_example_parallel',
          title: 'Example: Parallel (Different Workers)',
          content:
              '**Three workers each doing one haircut (45 min each):**\n'
              '• Worker A: Person 1 (9:00 - 9:45)\n'
              '• Worker B: Person 2 (9:00 - 9:45) at same time\n'
              '• Worker C: Person 3 (9:00 - 9:45) at same time\n'
              '• **Total: 45 min**',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'group_time_combined',
          title: 'Combined View for Groups',
          content:
              'When booking for a group, Combined View is especially useful. It shows only time slots where ALL people in your group can be accommodated together, with the correct total duration.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'group_time_tip',
          title: '',
          content:
              'If your group is large or has many services, consider booking earlier in the day to ensure enough time before the shop closes.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'group_payment',
      title: 'Payment for Group Bookings',
      subtitle: 'How deposits and fees work',
      icon: Icons.payment,
      category: 'Group Bookings',
      order: 5,
      contents: [
        ManualContent(
          id: 'group_payment_deposit',
          title: 'Deposit Calculation',
          content:
              'For group bookings, the 30% deposit is calculated on the **total cost of all services for all people**.',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Total cost:** Sum of all services × quantities',
            '**Deposit:** 30% of total cost',
            '**Platform fee:** One fixed fee for the entire group booking',
            '**Total due now:** Deposit + platform fee',
          ],
        ),
        ManualContent(
          id: 'group_payment_example',
          title: 'Payment Example',
          content:
              '**Family of 4 with total GHS 500:**\n'
              '• Deposit (30%): GHS 150\n'
              '• Platform fee: GHS 2\n'
              '• **Pay now: GHS 152**\n'
              '• Pay after: GHS 350 (cash or app)',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'group_payment_cancellation',
          title: 'Cancellation for Groups',
          content: 'If you cancel a group booking:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Full group cancellation:** Entire deposit and fee are non-refundable',
            '**Partial cancellation:** If some people can\'t make it, you may lose their portion of the deposit',
            '**Rescheduling:** You can reschedule the whole group (deposit transfers)',
          ],
        ),
        ManualContent(
          id: 'group_payment_important',
          title: '',
          content:
              'The platform fee is charged once per group booking, not per person. You save on fees by booking as a group!',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'group_scenarios',
      title: 'Common Group Scenarios',
      subtitle: 'Real examples to help you understand',
      icon: Icons.format_list_bulleted,
      category: 'Group Bookings',
      order: 6,
      contents: [
        ManualContent(
          id: 'scenario_family',
          title: 'Scenario 1: Family Haircut Day',
          content:
              '**The Mensah family (4 people) needs haircuts:**\n'
              '• Dad: Fade haircut (45 min, GHS 40)\n'
              '• Mom: Trim (30 min, GHS 35)\n'
              '• Son (10): Kids haircut (30 min, GHS 25)\n'
              '• Daughter (8): Braids (2 hours, GHS 80)\n\n'
              '**What they do:**\n'
              '1. Select "Haircut" → set quantity 3\n'
              '2. Select "Braids" → set quantity 1\n'
              '3. Choose workers: Dad → John, Son → Michael, Daughter → Sarah\n'
              '4. Pick a time that works for everyone\n'
              '5. Pay deposit: GHS 54 (30% of GHS 180) + GHS 2 fee = GHS 56\n'
              '6. After service, pay remaining GHS 126',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'scenario_friends',
          title: 'Scenario 2: Friends Day Out',
          content:
              '**Three friends want different services:**\n'
              '• Friend 1: Beard trim (30 min, GHS 25)\n'
              '• Friend 2: Haircut + Beard (75 min, GHS 65)\n'
              '• Friend 3: Full color (2 hours, GHS 120)\n\n'
              '**What they do:**\n'
              '1. Select each service with quantity 1\n'
              '2. Choose their preferred workers\n'
              '3. System finds a time that works for all\n'
              '4. Pay deposit: GHS 63 (30% of GHS 210) + GHS 2 fee = GHS 65',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'scenario_bridal',
          title: 'Scenario 3: Bridal Party',
          content:
              '**Bride + 3 bridesmaids getting ready:**\n'
              '• Bride: Hair + Makeup (3 hours, GHS 300)\n'
              '• Each bridesmaid: Hair styling (1 hour, GHS 80 each)\n\n'
              '**What they do:**\n'
              '1. Select Bride services with quantity 1\n'
              '2. Select Hair styling with quantity 3\n'
              '3. Assign different workers to each person\n'
              '4. Book a morning slot to have enough time\n'
              '5. Pay deposit: GHS 162 (30% of GHS 540) + GHS 2 fee = GHS 164',
          type: ManualContentType.text,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_group_what',
        question: 'What is a group booking?',
        answer:
            'A group booking allows you to book services for multiple people at once. Instead of making separate bookings for each person, you can book everything together in one go. This is perfect for families, friends, or any group wanting services together.',
        category: 'Group Bookings',
        order: 1,
      ),
      FAQModel(
        id: 'faq_group_quantity',
        question: 'How do I increase the number of people?',
        answer:
            'After selecting a service, look for the **+** and **-** buttons. Tap **+** to increase the quantity (number of people) for that service. The price updates automatically. You cannot exceed the maximum quantity shown for that service.',
        category: 'Group Bookings',
        order: 2,
      ),
      FAQModel(
        id: 'faq_group_different_services',
        question: 'Can we book different services for different people?',
        answer:
            'Absolutely! You can select multiple services and set different quantities for each. For example, you can book 2 haircuts and 1 braid service all in the same booking. The system handles everything together.',
        category: 'Group Bookings',
        order: 3,
      ),
      FAQModel(
        id: 'faq_group_workers',
        question: 'Can different people have different workers?',
        answer:
            'Yes! When you book for a group, you\'ll see each person listed separately. You can tap on each person to choose their preferred worker. This is great when different people have different preferences.',
        category: 'Group Bookings',
        order: 4,
      ),
      FAQModel(
        id: 'faq_group_payment',
        question: 'How is payment calculated for groups?',
        answer:
            'The 30% deposit is calculated on the TOTAL cost of all services for all people. The platform fee is charged once for the entire group booking (not per person). After service, you pay the remaining 70% total (cash or app).',
        category: 'Group Bookings',
        order: 5,
      ),
      FAQModel(
        id: 'faq_group_cancel',
        question: 'What if one person cancels?',
        answer:
            'If someone in your group cancels, the deposit for their portion is non-refundable. The rest of the group can still proceed. Contact the shop through the app to adjust the booking.',
        category: 'Group Bookings',
        order: 6,
      ),
      FAQModel(
        id: 'faq_group_time',
        question: 'How is the total appointment time calculated?',
        answer:
            'The system calculates total time based on: service durations × quantities, plus buffer times between services. If you choose different workers who can work in parallel, the total time may be shorter.',
        category: 'Group Bookings',
        order: 7,
      ),
      FAQModel(
        id: 'faq_group_max',
        question: 'Is there a maximum group size?',
        answer:
            'Each service has a maximum quantity limit shown when booking. If you need to book for a very large group, you may need to make multiple bookings or contact the shop directly.',
        category: 'Group Bookings',
        order: 8,
      ),
      FAQModel(
        id: 'faq_group_kids',
        question: 'Can I book for my children?',
        answer:
            'Yes! Group bookings are perfect for families. You can book for yourself and your children together. Just set the quantity to include everyone. For kids services, look for "Kids" options.',
        category: 'Group Bookings',
        order: 9,
      ),
      FAQModel(
        id: 'faq_group_check_in',
        question: 'How does check-in work for groups?',
        answer:
            'When you arrive, let the shop know you have a group booking. They\'ll check the main booking and direct everyone to their assigned workers. Arrive 10-15 minutes early for large groups.',
        category: 'Group Bookings',
        order: 10,
      ),
      FAQModel(
        id: 'faq_group_split_payment',
        question: 'Can we split the payment?',
        answer:
            'The deposit is paid by the person making the booking. After service, you can split the remaining 70% however you like - cash, individual app payments, or one person paying for all.',
        category: 'Group Bookings',
        order: 11,
      ),
      FAQModel(
        id: 'faq_group_reschedule',
        question: 'Can we reschedule a group booking?',
        answer:
            'Yes, you can reschedule the entire group booking up to 24 hours before the appointment. The deposit transfers to the new time. If only some people need to reschedule, contact the shop.',
        category: 'Group Bookings',
        order: 12,
      ),
    ];
  }
}
