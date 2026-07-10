// lib/features/documentation/data/docs/booking_docs/payment_fees_explained.dart
import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class PaymentFeesExplainedDocs implements DocumentationModule {
  @override
  int get order => 4;

  @override
  String getTitle(BuildContext context) => 'Payment & Fees Explained';

  @override
  String get id => 'paymentFeesExplained';

  @override
  String getSubtitle(BuildContext context) =>
      'A clear breakdown of deposits, fees, and payments';

  @override
  IconData get icon => Icons.payment;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'payment_overview',
      title: 'How Payment Works',
      subtitle: 'Simple, transparent, secure',
      icon: Icons.account_balance_wallet,
      category: 'Payment',
      order: 1,
      contents: [
        ManualContent(
          id: 'payment_summary',
          title: 'Payment at a Glance',
          content:
              'Our payment system is designed to be fair for both clients and shop owners. Here\'s the simple breakdown:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**30% Deposit:** Paid at booking to secure your appointment',
            '**Platform Fee:** Small fixed fee (e.g., GHS 2) charged by the app',
            '**Remaining 70%:** Paid after your service is complete',
            '**Two Ways to Pay Remaining:** Cash or via app',
          ],
        ),
        ManualContent(
          id: 'payment_example_quick',
          title: 'Quick Example',
          content:
              '**Service cost: GHS 100**\n'
              '• At booking: Pay GHS 30 (deposit) + GHS 2 (fee) = GHS 32\n'
              '• After service: Pay GHS 70 (cash or app)\n'
              '• Total to shop: GHS 100\n'
              '• Platform fee: GHS 2',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'payment_important',
          title: '',
          content:
              'The platform fee is charged by the app, not the shop. It helps us maintain the platform and provide you with a great booking experience.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'deposit_explained',
      title: 'The 30% Deposit',
      subtitle: 'Why it\'s needed and how it works',
      icon: Icons.lock,
      category: 'Payment',
      order: 2,
      contents: [
        ManualContent(
          id: 'deposit_why',
          title: 'Why Do We Require a Deposit?',
          content: 'The 30% deposit protects both you and the shop:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**For you:** Your slot is guaranteed – no one else can book it',
            '**For the shop:** Workers are compensated if you cancel last minute',
            '**For everyone:** Reduces no-shows, keeping prices fair',
          ],
        ),
        ManualContent(
          id: 'deposit_calculation',
          title: 'How the Deposit is Calculated',
          content:
              'The deposit is always **30% of the total service cost**. This includes:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Single service:** 30% of that service price',
            '**Multiple services:** 30% of all services combined',
            '**Group bookings:** 30% of total for all people',
          ],
        ),
        ManualContent(
          id: 'deposit_examples',
          title: 'Deposit Examples',
          content:
              '**Single Service:**\n'
              '• Haircut (GHS 45) → Deposit GHS 13.50\n\n'
              '**Multiple Services:**\n'
              '• Haircut (GHS 45) + Beard Trim (GHS 25) = GHS 70 total\n'
              '• Deposit: GHS 21\n\n'
              '**Group Booking (3 people):**\n'
              '• 3 × Haircut (GHS 45 each) = GHS 135 total\n'
              '• Deposit: GHS 40.50',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'deposit_non_refundable',
          title: 'Deposit Refund Policy',
          content: 'The 30% deposit is **non-refundable**. This means:',
          numberPrefix: '3',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**If you cancel:** Deposit is not returned',
            '**If you don\'t show up:** Deposit is not returned',
            '**If you reschedule:** Deposit transfers to new time',
            '**If shop cancels:** Full deposit refunded',
          ],
        ),
        ManualContent(
          id: 'deposit_warning',
          title: '',
          content:
              'Please be sure about your booking before paying the deposit. While you can reschedule, the deposit cannot be refunded if you cancel.',
          type: ManualContentType.warning,
        ),
      ],
    ),
    ManualSection(
      id: 'platform_fee',
      title: 'Platform Fee',
      subtitle: 'The small fee that keeps the app running',
      icon: Icons.apps,
      category: 'Payment',
      order: 3,
      contents: [
        ManualContent(
          id: 'fee_what',
          title: 'What is the Platform Fee?',
          content:
              'The platform fee is a small fixed charge (e.g., GHS 2) that goes to the app, not the shop. It covers:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**App development** and maintenance',
            '**Customer support** and dispute resolution',
            '**Payment processing** costs',
            '**New features** and improvements',
          ],
        ),
        ManualContent(
          id: 'fee_how',
          title: 'How the Fee is Charged',
          content: 'Important things to know about the platform fee:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Fixed amount** (not a percentage) – e.g., GHS 2 per booking',
            '**Charged once per booking** – not per service or per person',
            '**Non-refundable** – even if you cancel',
            '**Clearly shown** before you confirm payment',
          ],
        ),
        ManualContent(
          id: 'fee_examples',
          title: 'Platform Fee Examples',
          content:
              '**Single person, one service:** GHS 2 fee\n'
              '**Single person, multiple services:** GHS 2 fee (still one booking!)\n'
              '**Family of 4 booking together:** GHS 2 fee (entire group)\n\n'
              '**Compare to booking separately:**\n'
              '• 4 separate bookings = 4 × GHS 2 = GHS 8 in fees\n'
              '• 1 group booking = GHS 2 fee – **you save GHS 6!**',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'fee_tip',
          title: '',
          content:
              'Booking as a group saves you money on fees! Instead of paying the platform fee for each person, you pay just one fee for the entire group booking.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'remaining_payment',
      title: 'Paying the Remaining 70%',
      subtitle: 'Two convenient options',
      icon: Icons.payments,
      category: 'Payment',
      order: 4,
      contents: [
        ManualContent(
          id: 'remaining_overview',
          title: 'After Your Service',
          content:
              'Once your service is complete, you have two ways to pay the remaining 70%:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Option 1: Cash** – Pay the worker or shop directly',
            '**Option 2: Via App** – Pay through the app using your preferred method',
          ],
        ),
        ManualContent(
          id: 'remaining_cash',
          title: 'Paying with Cash',
          content: 'If you choose to pay the remaining balance in cash:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Simply hand the cash to your worker or at the counter',
            'You\'ll still receive a receipt through the app',
            'The shop will mark the payment as received',
            'No additional fees',
          ],
        ),
        ManualContent(
          id: 'remaining_app',
          title: 'Paying Through the App',
          content: 'If you prefer to pay via the app:',
          numberPrefix: '3',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Open your booking in "My Bookings"',
            'Tap "Pay Remaining Balance"',
            'Choose your payment method (card, mobile money, etc.)',
            'Complete payment – instant confirmation',
            'Receipt saved in the app',
          ],
        ),
        ManualContent(
          id: 'remaining_choice',
          title: 'Which Option Should You Choose?',
          content:
              '**Choose cash if:** You prefer physical payment, have cash on hand, or want to tip in cash\n\n'
              '**Choose app if:** You want a digital record, don\'t carry cash, or prefer using mobile money/cards',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'remaining_important',
          title: '',
          content:
              'The remaining 70% is paid to the shop, not the platform. No additional platform fee is charged at this stage.',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'payment_timing',
      title: 'When Payments Happen',
      subtitle: 'A timeline of when you pay',
      icon: Icons.timeline,
      category: 'Payment',
      order: 5,
      contents: [
        ManualContent(
          id: 'timeline_at_booking',
          title: 'At Booking Time',
          content:
              '**What you pay:**\n'
              '• 30% deposit\n'
              '• Platform fee (e.g., GHS 2)\n\n'
              '**What happens:** Your slot is secured immediately',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'timeline_before',
          title: 'Before Appointment',
          content:
              '**Nothing to pay** – just show up at your scheduled time!\n\n'
              'You\'ll receive reminders 24 hours and 1 hour before.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'timeline_after',
          title: 'After Service',
          content:
              '**What you pay:**\n'
              '• Remaining 70% of total cost\n\n'
              '**How to pay:**\n'
              '• Cash (to worker or shop)\n'
              '• Via app (digital payment)',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'timeline_summary',
          title: 'Payment Summary Example',
          content:
              '**Total bill: GHS 200**\n'
              '━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
              '**At booking:** GHS 60 (deposit) + GHS 2 (fee) = GHS 62\n'
              '**After service:** GHS 140 (remaining)\n'
              '**Total to shop:** GHS 200\n'
              '**Platform fee:** GHS 2',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'cancellation_refunds',
      title: 'Cancellation & Refunds',
      subtitle: 'What happens when plans change',
      icon: Icons.cancel,
      category: 'Payment',
      order: 6,
      contents: [
        ManualContent(
          id: 'cancel_client',
          title: 'If You Cancel',
          content:
              '**You cancel more than 24 hours before:**\n'
              '• Deposit: ❌ Non-refundable\n'
              '• Platform fee: ❌ Non-refundable\n'
              '• Remaining 70%: Not charged\n\n'
              '**You cancel within 24 hours:**\n'
              '• Deposit: ❌ Non-refundable\n'
              '• Platform fee: ❌ Non-refundable\n'
              '• Remaining 70%: Not charged\n'
              '• Note: Last-minute cancellations may affect your account standing',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'cancel_no_show',
          title: 'If You Don\'t Show Up',
          content:
              '**No-show policy:**\n'
              '• Deposit: ❌ Forfeited\n'
              '• Platform fee: ❌ Forfeited\n'
              '• Remaining 70%: Not charged\n'
              '• Account: Marked as no-show\n'
              '• Repeated no-shows may result in account restrictions',
          type: ManualContentType.warning,
        ),
        ManualContent(
          id: 'cancel_shop',
          title: 'If the Shop Cancels',
          content:
              '**Shop cancels for any reason:**\n'
              '• Deposit: ✅ Full refund\n'
              '• Platform fee: ✅ Full refund\n'
              '• Remaining 70%: Not applicable\n'
              '• You\'ll receive notification and refund automatically',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'cancel_reschedule',
          title: 'Rescheduling vs Cancelling',
          content:
              '**Rescheduling** (changing time/date):\n'
              '• Deposit transfers to new booking\n'
              '• Platform fee transfers (no additional fee)\n'
              '• Available up to 24 hours before\n\n'
              '**Cancelling** (completely):\n'
              '• Deposit and fee are forfeited\n'
              '• Must rebook and pay deposit again',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'cancel_tip',
          title: '',
          content:
              'If you can\'t make it, try to reschedule instead of cancelling. Your deposit transfers and you won\'t lose your money!',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'group_payment',
      title: 'Payment for Group Bookings',
      subtitle: 'How it works when booking for multiple people',
      icon: Icons.group,
      category: 'Payment',
      order: 7,
      contents: [
        ManualContent(
          id: 'group_deposit',
          title: 'Deposit for Groups',
          content:
              'For group bookings, the 30% deposit is calculated on the **total cost for everyone**.',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Example:** 4 people × GHS 50 each = GHS 200 total',
            '**Deposit:** 30% of GHS 200 = GHS 60',
            '**Paid by:** One person (the booker)',
          ],
        ),
        ManualContent(
          id: 'group_fee',
          title: 'Platform Fee for Groups',
          content:
              '**Great news!** The platform fee is charged **once per booking**, not per person.',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Example:** Family of 4 booking together',
            '**Fee:** GHS 2 total (not GHS 8)',
            '**Savings:** GHS 6 compared to booking separately',
          ],
        ),
        ManualContent(
          id: 'group_remaining',
          title: 'Paying the Remaining 70% for Groups',
          content: 'After the service, you have flexibility:',
          numberPrefix: '3',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**One person pays all:** Pay total remaining in cash or app',
            '**Split the bill:** Each person pays their share (cash to shop or individual app payments)',
            '**Mix and match:** Some pay cash, others use app',
          ],
        ),
        ManualContent(
          id: 'group_cancellation',
          title: 'Group Cancellations',
          content:
              '**If one person cancels:**\n'
              '• Their portion of the deposit is forfeited\n'
              '• The rest of the group can proceed\n'
              '• Contact shop to adjust\n\n'
              '**If entire group cancels:**\n'
              '• Full deposit and fee forfeited (standard policy)',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'group_saving',
          title: 'Group Savings Example',
          content:
              '**Family of 4 booking separately vs together:**\n\n'
              '**Separate bookings:**\n'
              '• 4 × GHS 2 platform fee = GHS 8 in fees\n\n'
              '**Group booking:**\n'
              '• 1 × GHS 2 platform fee = GHS 2\n'
              '• **You save GHS 6!**',
          type: ManualContentType.important,
        ),
      ],
    ),
    ManualSection(
      id: 'payment_methods',
      title: 'Accepted Payment Methods',
      subtitle: 'How you can pay',
      icon: Icons.credit_card,
      category: 'Payment',
      order: 8,
      contents: [
        ManualContent(
          id: 'methods_deposit',
          title: 'For Deposits (at booking)',
          content: 'You can pay your deposit using:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Credit/Debit Cards** (Visa, Mastercard, etc.)',
            '**Mobile Money** (MTN, Vodafone, AirtelTigo)',
            '**Bank Transfers** (instant payment)',
            '**Apple Pay / Google Pay** (where available)',
          ],
        ),
        ManualContent(
          id: 'methods_remaining',
          title: 'For Remaining Balance (after service)',
          content: 'After your service, you can pay the remaining 70% via:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Cash** (pay directly to worker or shop)',
            '**Mobile Money** (send to shop number)',
            '**Card** (if shop has card reader)',
            '**App Payment** (through the app)',
          ],
        ),
        ManualContent(
          id: 'methods_security',
          title: 'Payment Security',
          content: 'All payments through the app are:',
          numberPrefix: '3',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Encrypted** – your information is safe',
            '**PCI compliant** – meets security standards',
            '**Protected** – fraud monitoring in place',
            '**Receipt provided** – digital record of every payment',
          ],
        ),
        ManualContent(
          id: 'methods_tip',
          title: '',
          content:
              'Save your payment details in the app for faster checkout next time!',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'receipts',
      title: 'Receipts & Records',
      subtitle: 'Keeping track of your payments',
      icon: Icons.receipt,
      category: 'Payment',
      order: 9,
      contents: [
        ManualContent(
          id: 'receipt_what',
          title: 'What You\'ll Receive',
          content: 'For every payment, you\'ll get:',
          numberPrefix: '1',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Booking confirmation receipt** (at booking)',
            '**Deposit payment receipt** (immediate)',
            '**Final payment receipt** (after service)',
            '**Email copy** sent to your registered email',
            '**In-app record** in "My Bookings"',
          ],
        ),
        ManualContent(
          id: 'receipt_info',
          title: 'What\'s on Your Receipt',
          content: 'Each receipt shows:',
          numberPrefix: '2',
          type: ManualContentType.bulletList,
          bulletPoints: [
            '**Shop name** and location',
            '**Services booked** with quantities',
            '**Workers assigned**',
            '**Date and time** of appointment',
            '**Amount paid** (deposit/fee/remaining)',
            '**Payment method** used',
            '**Transaction reference** number',
          ],
        ),
        ManualContent(
          id: 'receipt_access',
          title: 'How to Access Receipts',
          content: 'To view your payment history:',
          numberPrefix: '3',
          type: ManualContentType.bulletList,
          bulletPoints: [
            'Go to **Profile** tab',
            'Tap **Payment History**',
            'See all transactions',
            'Tap any receipt to view details',
            'Share or download as PDF',
          ],
        ),
      ],
    ),
    ManualSection(
      id: 'payment_faq',
      title: 'Common Payment Questions',
      subtitle: 'Quick answers',
      icon: Icons.help,
      category: 'Payment',
      order: 10,
      contents: [
        ManualContent(
          id: 'payment_faq_1',
          title: 'Is the deposit really non-refundable?',
          content:
              'Yes, the 30% deposit is non-refundable by policy. This protects workers\' time and discourages last-minute cancellations. The only exception is if the shop cancels on you.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'payment_faq_2',
          title: 'Why a deposit instead of full payment?',
          content:
              'The deposit system is designed to be fair to everyone:\n'
              '• **You:** Only pay 30% upfront, not the full amount\n'
              '• **Shop:** Gets some compensation if you cancel\n'
              '• **Workers:** Time is valued and protected',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'payment_faq_3',
          title: 'Can I pay the full amount upfront?',
          content:
              'Currently, we only collect the 30% deposit at booking. The remaining 70% is paid after service to ensure you\'re happy with the result before paying in full.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'payment_faq_4',
          title: 'What if I want to add a tip?',
          content:
              'Great question! Tips can be added when paying the remaining 70% via the app, or you can tip in cash directly to your worker. 100% of tips go to the worker.',
          type: ManualContentType.text,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_payment_deposit',
        question: 'Why is the deposit non-refundable?',
        answer:
            'The deposit compensates workers for holding time exclusively for you. When you book a slot, that time can\'t be sold to someone else. The deposit policy discourages last-minute cancellations and no-shows, which helps keep prices fair for everyone.',
        category: 'Payment',
        order: 1,
      ),
      FAQModel(
        id: 'faq_payment_platform_fee',
        question: 'What exactly is the platform fee for?',
        answer:
            'The platform fee (e.g., GHS 2) helps us maintain the app, provide customer support, process payments securely, and develop new features. It\'s a small fixed fee that keeps the platform running smoothly for both clients and shops.',
        category: 'Payment',
        order: 2,
      ),
      FAQModel(
        id: 'faq_payment_remaining',
        question: 'Can I really pay the remaining amount in cash?',
        answer:
            'Yes! Many shops accept cash for the remaining 70%. You can also choose to pay through the app if you prefer digital payments. The choice is yours at the time of service.',
        category: 'Payment',
        order: 3,
      ),
      FAQModel(
        id: 'faq_payment_group_fee',
        question: 'How is the platform fee calculated for groups?',
        answer:
            'The platform fee is charged **once per booking**, not per person. So if you book for a family of 4, you pay just one GHS 2 fee instead of four separate fees. This makes group bookings more economical!',
        category: 'Payment',
        order: 4,
      ),
      FAQModel(
        id: 'faq_payment_refund',
        question: 'When would I get a refund?',
        answer:
            'Refunds are issued only if the shop cancels your booking. In that case, both your deposit and platform fee are fully refunded. If you cancel, the deposit and fee are non-refundable by policy.',
        category: 'Payment',
        order: 5,
      ),
      FAQModel(
        id: 'faq_payment_methods',
        question: 'What payment methods are accepted?',
        answer:
            'For deposits: Credit/debit cards, mobile money, bank transfers, and digital wallets. For remaining balance: Cash or any of the digital methods through the app. Available options may vary by region.',
        category: 'Payment',
        order: 6,
      ),
      FAQModel(
        id: 'faq_payment_tip',
        question: 'How do I tip my worker?',
        answer:
            'You can tip your worker in two ways:\n'
            '1. **Cash:** Give directly to your worker after service\n'
            '2. **Via App:** Add a tip when paying the remaining 70%\n\n'
            '100% of tips go directly to your worker!',
        category: 'Payment',
        order: 7,
      ),
      FAQModel(
        id: 'faq_payment_receipt',
        question: 'How do I get a receipt?',
        answer:
            'Receipts are automatically generated and sent to your email. You can also access all receipts in the app under Profile → Payment History. Each receipt shows full details of your transaction.',
        category: 'Payment',
        order: 8,
      ),
      FAQModel(
        id: 'faq_payment_split',
        question: 'Can we split the bill for group bookings?',
        answer:
            'Yes! For group bookings, you can split the remaining 70% however you like:\n'
            '• One person pays all (cash or app)\n'
            '• Each person pays their share (cash to shop)\n'
            '• Mix of cash and app payments\n\n'
            'The deposit is paid by the person making the booking.',
        category: 'Payment',
        order: 9,
      ),
      FAQModel(
        id: 'faq_payment_emergency',
        question: 'What if I have an emergency and can\'t make it?',
        answer:
            'We understand emergencies happen. While the deposit is officially non-refundable, you can contact the shop directly through the app. Some shops may offer credit toward a future booking at their discretion. The platform fee cannot be refunded.',
        category: 'Payment',
        order: 10,
      ),
      FAQModel(
        id: 'faq_payment_saved',
        question: 'Can I save my payment details for faster booking?',
        answer:
            'Yes! In your Profile settings, you can save payment methods securely. This makes future bookings faster – just confirm and pay with one tap. Your information is encrypted and stored securely.',
        category: 'Payment',
        order: 11,
      ),
      FAQModel(
        id: 'faq_payment_security',
        question: 'Is my payment information secure?',
        answer:
            'Absolutely. All payments are processed through secure, PCI-compliant gateways. Your payment details are encrypted and never stored in plain text. We use industry-standard security measures to protect your information.',
        category: 'Payment',
        order: 12,
      ),
    ];
  }
}
