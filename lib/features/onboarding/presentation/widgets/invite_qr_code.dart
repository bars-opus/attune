import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:qr_flutter/qr_flutter.dart';

class InviteQrCode extends StatelessWidget {
  final String data;
  const InviteQrCode({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: QrImageView(
        data: data,

        //  invite.deepLink,
        version: QrVersions.auto,
        size: 170.w,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.primary,
      ),
    );
  }
}
