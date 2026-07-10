import 'dart:async';
import 'dart:io';
import 'dart:math';

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
  ChatError(this.category, {String? correlationId, this.cause})
    : correlationId = correlationId ?? newCorrelationId();

  final ChatErrorCategory category;
  final String correlationId;

  /// The original error, retained for privacy-safe *logging only* — never
  /// surfaced to the UI.
  final Object? cause;

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
  factory ChatError.from(Object? error, {String? correlationId}) {
    if (error is ChatError) return error;

    if (error is TimeoutException || error is SocketException) {
      return ChatError(
        ChatErrorCategory.offline,
        correlationId: correlationId,
        cause: error,
      );
    }

    if (error is ChatImageRejectedSignal) {
      return ChatError(
        ChatErrorCategory.mediaRejected,
        correlationId: correlationId,
        cause: error,
      );
    }

    if (error is PostgrestException) {
      return ChatError(
        _categorizePostgrest(error),
        correlationId: correlationId,
        cause: error,
      );
    }

    if (error is StorageException) {
      return ChatError(
        ChatErrorCategory.mediaRejected,
        correlationId: correlationId,
        cause: error,
      );
    }

    if (error is AuthException) {
      return ChatError(
        ChatErrorCategory.unauthenticated,
        correlationId: correlationId,
        cause: error,
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
      );
    }

    return ChatError(
      ChatErrorCategory.unknown,
      correlationId: correlationId,
      cause: error,
    );
  }

  /// Rebuilds a category from its persisted [queueCode] (Spec 4.2 restore).
  static ChatErrorCategory categoryFromCode(String? code) {
    return ChatErrorCategory.values.firstWhere(
      (value) => value.name == code,
      orElse: () => ChatErrorCategory.unknown,
    );
  }

  static ChatErrorCategory _categorizePostgrest(PostgrestException error) {
    final code = error.code;
    if (code == '42501') return ChatErrorCategory.unauthenticated;
    if (code == '429') return ChatErrorCategory.rateLimited;
    if (code == '23505') {
      // Duplicate is handled as success-with-fetch by callers; if it reaches
      // here treat as transient.
      return ChatErrorCategory.unknown;
    }

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
    if (message.contains('rate') || message.contains('too many')) {
      return ChatErrorCategory.rateLimited;
    }
    if (message.contains('intent') || message.contains('upload')) {
      return ChatErrorCategory.mediaRejected;
    }
    return ChatErrorCategory.unavailable;
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
        return "That image could not be sent. Try a different one.";
      case ChatErrorCategory.rateLimited:
        return "You're sending very quickly. Please wait a moment and try again.";
      case ChatErrorCategory.unavailable:
        return "Chat is temporarily unavailable. Please try again shortly.";
      case ChatErrorCategory.unknown:
        return "Message not sent. Tap to retry.";
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
