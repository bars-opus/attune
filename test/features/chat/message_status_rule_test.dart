import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_status_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('thumbnailDecodeSize', () {
    test('portrait constrains width (the shorter side)', () {
      final s = thumbnailDecodeSize(
        displayPx: 660,
        mediaWidth: 1200,
        mediaHeight: 1600,
      );
      expect(s.width, 660);
      expect(s.height, isNull);
    });
    test('landscape constrains height', () {
      final s = thumbnailDecodeSize(
        displayPx: 660,
        mediaWidth: 1600,
        mediaHeight: 1200,
      );
      expect(s.width, isNull);
      expect(s.height, 660);
    });
    test('a box taller than wide binds the side cover needs (238 x 300)', () {
      // 3:4 is narrower than the box: width-bound at the box width.
      final portrait = thumbnailDecodeSize(
        displayPx: 238,
        displayHeightPx: 300,
        mediaWidth: 1200,
        mediaHeight: 1600,
      );
      expect(portrait.width, 238);
      expect(portrait.height, isNull);
      // 9:10 is wider than the box: a 238-wide decode would be 264 tall and
      // upscale; height-bound instead.
      final nearSquare = thumbnailDecodeSize(
        displayPx: 238,
        displayHeightPx: 300,
        mediaWidth: 900,
        mediaHeight: 1000,
      );
      expect(nearSquare.width, isNull);
      expect(nearSquare.height, 300);
      // Unknown: twice the longer side.
      final unknown = thumbnailDecodeSize(displayPx: 238, displayHeightPx: 300);
      expect(unknown.width, 600);
      expect(unknown.height, isNull);
    });
    test('unknown dimensions keep twice the width (full-res local pick)', () {
      final s = thumbnailDecodeSize(displayPx: 660);
      expect(s.width, 1320);
      expect(s.height, isNull);
    });
  });

  group('showsDeliveryStatus', () {
    test('partner rows never', () {
      expect(
        showsDeliveryStatus(
          isMine: false,
          isNewestOwn: true,
          isGroupEnd: true,
          status: MessageStatus.read,
        ),
        isFalse,
      );
    });
    test('newest own and group ends do', () {
      expect(
        showsDeliveryStatus(
          isMine: true,
          isNewestOwn: true,
          isGroupEnd: false,
          status: MessageStatus.sent,
        ),
        isTrue,
      );
      expect(
        showsDeliveryStatus(
          isMine: true,
          isNewestOwn: false,
          isGroupEnd: true,
          status: MessageStatus.delivered,
        ),
        isTrue,
      );
    });
    test('a settled mid-group row does not; a pending/failed one always does', () {
      expect(
        showsDeliveryStatus(
          isMine: true,
          isNewestOwn: false,
          isGroupEnd: false,
          status: MessageStatus.read,
        ),
        isFalse,
      );
      for (final s in [
        MessageStatus.queued,
        MessageStatus.sending,
        MessageStatus.failed,
      ]) {
        expect(
          showsDeliveryStatus(
            isMine: true,
            isNewestOwn: false,
            isGroupEnd: false,
            status: s,
          ),
          isTrue,
          reason: '$s',
        );
      }
    });
  });
}
