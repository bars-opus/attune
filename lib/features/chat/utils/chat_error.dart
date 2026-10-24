import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The coarse domain error categories chat repositories map every internal
/// failure to (Spec 12.3). UI copy derives only from the category — never from
/// raw SQL, stack traces, policy names, storage paths, safety state, model
/// output, or another user's existence.
enum ChatErrorCategory {
  offline,
  unauthenticated,
  relationshipInactive,
  relationshipArchived,
  payloadInvalid,
  mediaRejected,
  rateLimited,
  unavailable,
  unknown,
}

/// A categorized, user-safe chat error. Carries a short [correlationId] so a
/// support/log line can be tied to a user report without exposing any content
/// (Spec 12.3, 15).
class ChatError implements Exception {
  ChatError(
    this.category, {
    String? correlationId,
    this.cause,
    this.mediaType,
  }) : correlationId = correlationId ?? newCorrelationId();

  final ChatErrorCategory category;
  final String correlationId;

  /// The original error, retained for privacy-safe *logging only* — never
  /// surfaced to the UI.
  final Object? cause;

  /// 'image' | 'audio' | 'video' | null — only shapes the copy, never the
  /// category.
  final String? mediaType;

  /// The same error, worded for a PendingSend's [mediaType]. A streak is a
  /// photo or a clip, so its wording comes from [mimeType] (no mime: the
  /// clip, the streak's original default).
  ChatError forMedia(String? mediaType, {String? mimeType}) {
    final kind =
        mediaType == 'streak'
            ? (mimeType?.startsWith('image/') ?? false ? 'image' : 'video')
            : mediaType;
    if (kind == null || kind == this.mediaType) return this;
    return ChatError(
      category,
      correlationId: correlationId,
      cause: cause,
      mediaType: kind,
    );
  }

  /// The error a send settles as once its automatic attempts are spent. A
  /// storage refusal that was worth retrying (403: an upload intent or
  /// token that expired mid-upload) has now been refused on every fresh
  /// intent, so it reads as a rejection of that media; anything else is
  /// unchanged.
  ChatError afterAttemptCap() {
    if (category != ChatErrorCategory.unknown || cause is! StorageException) {
      return this;
    }
    return ChatError(
      ChatErrorCategory.mediaRejected,
      correlationId: correlationId,
      cause: cause,
      mediaType: mediaType,
    );
  }

  /// Storage answered 413: the file is over the bucket's size limit.
  bool get _isTooLarge {
    final source = cause;
    return source is StorageException && source.statusCode == '413';
  }

  /// True when an automatic retry can still make progress.
  bool get isTransient =>
      category == ChatErrorCategory.offline ||
      category == ChatErrorCategory.unavailable ||
      category == ChatErrorCategory.rateLimited ||
      category == ChatErrorCategory.unknown;

  /// True when the send can never succeed without user action (a permanent
  /// failure in queue terms, Spec 4.2).
  bool get isPermanent =>
      category == ChatErrorCategory.unauthenticated ||
      category == ChatErrorCategory.relationshipInactive ||
      category == ChatErrorCategory.relationshipArchived ||
      category == ChatErrorCategory.payloadInvalid ||
      category == ChatErrorCategory.mediaRejected;

  /// Coarse queue error label persisted with a pending send (Spec 4.2). Content
  /// free; safe to store locally.
  String get queueCode => category.name;

  /// Maps a raw exception to a coarse category. Never returns the raw message.
  factory ChatError.from(
    Object? error, {
    String? correlationId,
    String? mediaType,
  }) {
    if (error is ChatError) return error.forMedia(mediaType);

    if (error is TimeoutException || error is SocketException) {
      return ChatError(
        ChatErrorCategory.offline,
        correlationId: correlationId,
        cause: error,
        mediaType: mediaType,
      );
    }

    if (error is ChatImageRejectedSignal) {
      return ChatError(
        ChatErrorCategory.mediaRejected,
        correlationId: correlationId,
        cause: error,
        mediaType: mediaType,
      );
    }

    if (error is PostgrestException) {
      return ChatError(
        _categorizePostgrest(error),
        correlationId: correlationId,
        cause: error,
        mediaType: mediaType,
      );
    }

    if (error is http.ClientException) {
      // The streaming uploader surfaces a dropped socket this way.
      return ChatError(
        ChatErrorCategory.offline,
        correlationId: correlationId,
        cause: error,
        mediaType: mediaType,
      );
    }

    if (error is StorageException) {
      return ChatError(
        categorizeStorageStatus(error.statusCode),
        correlationId: correlationId,
        cause: error,
        mediaType: mediaType,
      );
    }

    if (error is AuthException) {
      return ChatError(
        ChatErrorCategory.unauthenticated,
        correlationId: correlationId,
        cause: error,
        mediaType: mediaType,
      );
    }

    final text = error?.toString().toLowerCase() ?? '';
    if (text.contains('socket') ||
        text.contains('network') ||
        text.contains('connection') ||
        text.contains('timeout') ||
        text.contains('host')) {
      return ChatError(
        ChatErrorCategory.offline,
        correlationId: correlationId,
        cause: error,
        mediaType: mediaType,
      );
    }

    return ChatError(
      ChatErrorCategory.unknown,
      correlationId: correlationId,
      cause: error,
      mediaType: mediaType,
    );
  }

  /// What validate_message_media_before_insert raises (a bare P0001) when
  /// the key a row carries no longer passes: its 15-minute upload intent
  /// expired or was used, or the object is gone (latest body:
  /// 20260914150000_streak_size_ceiling.sql). Matched on the trigger's own
  /// RAISE text, here and nowhere else.
  static const staleMediaUploadRefusals = [
    'chat media upload intent is invalid or expired',
    'chat media object is missing',
    'chat media thumbnail upload intent is invalid or expired',
    'chat media thumbnail object is missing',
  ];

  /// Whether [error] is the insert trigger refusing a stored media key whose
  /// upload went stale — the bytes were uploaded, the insert came too late
  /// (offline right after, the app killed, a long upload on a slow link).
  /// The same key can never pass again; a fresh intent and upload will.
  static bool isStaleMediaUploadRefusal(Object? error) {
    if (error is! PostgrestException) return false;
    final message = error.message.toLowerCase();
    return staleMediaUploadRefusals.any(message.contains);
  }

  /// Rebuilds a category from its persisted [queueCode] (Spec 4.2 restore).
  static ChatErrorCategory categoryFromCode(String? code) {
    return ChatErrorCategory.values.firstWhere(
      (value) => value.name == code,
      orElse: () => ChatErrorCategory.unknown,
    );
  }

  /// Storage replies by HTTP status. Only a 4xx the client caused is a
  /// permanent rejection; everything else can succeed on retry (chat review
  /// #26 — a 503 used to fail the send on the first attempt).
  @visibleForTesting
  static ChatErrorCategory categorizeStorageStatus(String? statusCode) {
    final code = int.tryParse(statusCode ?? '');
    if (code == null) return ChatErrorCategory.unavailable;
    if (code == 429) return ChatErrorCategory.rateLimited;
    if (code >= 500) return ChatErrorCategory.unavailable;
    // 401: token refresh then retry. 408: a timeout, transport as in
    // [_isServerRejection]. 409: the retry requests a fresh intent (a new
    // object key), so a duplicate-object reply is not final either.
    if (code == 401 || code == 408 || code == 409) {
      return ChatErrorCategory.unavailable;
    }
    // 403: the storage policy refused the write. Usually the 15-minute
    // upload intent (or the token) expired during a slow upload, which a
    // fresh intent on retry fixes; a real policy refusal repeats on every
    // attempt. It counts toward the attempt cap, then settles as a media
    // rejection ([afterAttemptCap]).
    if (code == 403) return ChatErrorCategory.unknown;
    if (code >= 400) return ChatErrorCategory.mediaRejected;
    return ChatErrorCategory.unknown;
  }

  /// The rate-limit code our own RPCs and functions report
  /// (`story_intent_error('RATE_LIMITED')`, `RAISE EXCEPTION 'rate_limited'`,
  /// the edge functions' `code: "RATE_LIMITED"`). Matched whole, any case.
  static const serverRateLimitCode = 'rate_limited';

  /// Last-resort message fallback: whole rate-limit phrases only, never the
  /// bare substring "rate" ("generate_story_item failed", "separate").
  static final _rateLimitPhrase = RegExp(
    r'\b(?:rate[ _-]?limit(?:ed|s|ing)?|too many requests)\b',
    caseSensitive: false,
  );

  static bool _isRateLimitCode(String? value) =>
      value != null && value.trim().toLowerCase() == serverRateLimitCode;

  static ChatErrorCategory _categorizePostgrest(PostgrestException error) {
    // Structured first: the code (SQLSTATE, PGRST*, or the HTTP status the
    // client puts there when the body has none) decides before any message
    // word, so a gateway page or an unrelated RAISE text can't pick a
    // category by accident.
    final code = error.code;
    if (code == '42501') return ChatErrorCategory.unauthenticated;
    if (code == '429' || _isRateLimitCode(code)) {
      return ChatErrorCategory.rateLimited;
    }
    if (code == '23505') {
      // Duplicate is handled as success-with-fetch by callers; if it reaches
      // here treat as transient.
      return ChatErrorCategory.unknown;
    }
    if (_isTransport(code)) return ChatErrorCategory.unavailable;
    if (_isRateLimitCode(error.message)) return ChatErrorCategory.rateLimited;

    final message = error.message.toLowerCase();
    if (message.contains('archived')) {
      return ChatErrorCategory.relationshipArchived;
    }
    if (message.contains('active') || message.contains('inactive')) {
      return ChatErrorCategory.relationshipInactive;
    }
    if (message.contains('payload') ||
        message.contains('content') ||
        message.contains('check constraint') ||
        message.contains('violates')) {
      return ChatErrorCategory.payloadInvalid;
    }
    if (_rateLimitPhrase.hasMatch(message)) {
      return ChatErrorCategory.rateLimited;
    }
    if (message.contains('intent') || message.contains('upload')) {
      return ChatErrorCategory.mediaRejected;
    }
    // A real server rejection of THIS request — a trigger RAISE ("Reply
    // target message does not exist", "Story unavailable"), bad data, a
    // constraint, an undefined function, an HTTP 4xx, a PostgREST request
    // or schema error — cannot be fixed by retrying the same payload. It
    // counts toward the automatic attempt cap (Spec 4.2). Only
    // transport-shaped failures (HTTP 5xx / gateway / timeout codes,
    // PostgREST connection errors, no code at all) stay `unavailable`,
    // which never turns a message red.
    if (_isServerRejection(code)) return ChatErrorCategory.unknown;
    return ChatErrorCategory.unavailable;
  }

  /// Transport-shaped codes that no message word may override: HTTP 5xx
  /// and 408 (gateway / timeout), PostgREST connection (PGRST0xx) and JWT
  /// (PGRST3xx, e.g. PGRST301 expired across a resume) errors. A missing
  /// code is unavailable too, but only after the message checks.
  static bool _isTransport(String? code) {
    if (code == null) return false;
    if (code.startsWith('PGRST')) {
      final group = code.length > 5 ? code[5] : '';
      return group == '0' || group == '3';
    }
    if (code.length != 3) return false;
    final status = int.tryParse(code);
    return status != null && (status >= 500 || status == 408);
  }

  /// SQLSTATE classes P0 (PL/pgSQL RAISE / ASSERT), 22 (data exception), 23
  /// (integrity, except 23505 which callers reconcile) and 42 (syntax /
  /// access, except 42501 which is mapped to unauthenticated above); HTTP
  /// 4xx except 408 (a timeout) and 429 (mapped to rateLimited above); and
  /// PostgREST request (PGRST1xx) and schema-cache (PGRST2xx) errors.
  /// PGRST0xx (cannot reach the database) is transport.
  static bool _isServerRejection(String? code) {
    if (code == null) return false;
    if (code.startsWith('PGRST')) {
      final group = code.length > 5 ? code[5] : '';
      return group == '1' || group == '2';
    }
    if (code.length == 3) {
      final status = int.tryParse(code);
      return status != null &&
          status >= 400 &&
          status < 500 &&
          status != 408 &&
          status != 429;
    }
    if (code.length != 5) return false;
    switch (code.substring(0, 2)) {
      case 'P0':
      case '22':
        return true;
      case '23':
        return code != '23505';
      case '42':
        return code != '42501';
      default:
        return false;
    }
  }

  /// Short, actionable, PII-free copy for the category. Localization of these
  /// strings is a pre-launch gate item (Spec 11.4); the shapes are stable so a
  /// later l10n pass maps 1:1 to keys.
  String toUserMessage() {
    switch (category) {
      case ChatErrorCategory.offline:
        return "You appear to be offline. Your message will send when you reconnect.";
      case ChatErrorCategory.unauthenticated:
        return "You no longer have access to this conversation.";
      case ChatErrorCategory.relationshipInactive:
        return "This relationship chat is read-only.";
      case ChatErrorCategory.relationshipArchived:
        return "This conversation has been archived.";
      case ChatErrorCategory.payloadInvalid:
        return "This message could not be sent.";
      case ChatErrorCategory.mediaRejected:
        if (_isTooLarge) {
          switch (mediaType) {
            case 'audio':
              return "That voice message is too long to send.";
            case 'video':
              return "That video is too large to send — try a shorter clip.";
            default:
              return "That photo is too large to send.";
          }
        }
        switch (mediaType) {
          case 'audio':
            return "That voice message could not be sent. Try recording it again.";
          case 'video':
            return "That video could not be sent. Try a different one.";
          default:
            return "That image could not be sent. Try a different one.";
        }
      case ChatErrorCategory.rateLimited:
        return "You're sending very quickly. Please wait a moment and try again.";
      case ChatErrorCategory.unavailable:
        return "Chat is temporarily unavailable. Please try again shortly.";
      case ChatErrorCategory.unknown:
        return "Message not sent. Tap to retry.";
    }
  }

  /// Copy for a failure to LOAD the conversation. [toUserMessage] speaks
  /// for a send ("Message not sent", "will send when you reconnect"), and
  /// how a failure is categorized for the send queue must never put send
  /// words on a page read. Access and lifecycle copy is the same in both.
  String toLoadMessage() {
    switch (category) {
      case ChatErrorCategory.offline:
        return "You appear to be offline. Your messages will refresh when "
            "you reconnect.";
      case ChatErrorCategory.unauthenticated:
      case ChatErrorCategory.relationshipInactive:
      case ChatErrorCategory.relationshipArchived:
        return toUserMessage();
      case ChatErrorCategory.payloadInvalid:
      case ChatErrorCategory.mediaRejected:
      case ChatErrorCategory.rateLimited:
      case ChatErrorCategory.unavailable:
      case ChatErrorCategory.unknown:
        return "Your messages couldn't load right now. Try again in a moment.";
    }
  }

  static String newCorrelationId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random();
    return List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  @override
  String toString() => 'ChatError(${category.name}, id=$correlationId)';
}

/// Marker so the media-rejection path can be categorized without the chat_error
/// module depending on the image-preparer module directly.
class ChatImageRejectedSignal implements Exception {
  const ChatImageRejectedSignal(this.code);
  final String code;
}
