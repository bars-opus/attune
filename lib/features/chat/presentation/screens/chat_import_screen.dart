import 'dart:typed_data';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/repositories/chat_import_repository.dart';
import 'package:attune/features/chat/domain/entities/chat_import.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/services/whatsapp_chat_parser.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatImportScreen extends ConsumerStatefulWidget {
  const ChatImportScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<ChatImportScreen> createState() => _ChatImportScreenState();
}

class _ChatImportScreenState extends ConsumerState<ChatImportScreen> {
  static const _policyVersion = 'chat-import-1.0';
  final _parser = const WhatsAppChatParser();
  ParsedChatImport? _parsed;
  List<ChatImportRequest> _requests = const [];
  List<ChatImportJob> _jobs = const [];
  final Map<String, String> _mapping = {};
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(chatImportRepositoryProvider);
      final results = await Future.wait([
        repository.listRequests(widget.conversation.relationshipId),
        repository.listJobs(widget.conversation.relationshipId),
      ]);
      if (!mounted) return;
      setState(() {
        _requests = results[0] as List<ChatImportRequest>;
        _jobs = results[1] as List<ChatImportJob>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Import details are unavailable right now.';
      });
    }
  }

  Future<void> _pickExport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'zip'],
      withData: true,
    );
    if (result == null) return;
    final file = result.files.single;
    final Uint8List? bytes = file.bytes;
    if (bytes == null) {
      _showError('The selected file could not be read on this device.');
      return;
    }
    try {
      final parsed = _parser.parse(bytes: bytes, fileName: file.name);
      final user = ref.read(currentUserProvider);
      if (user == null) return;
      if (!mounted) return;
      setState(() {
        _parsed = parsed;
        _mapping.clear();
        _error = null;
      });
    } on ChatImportParseException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError("We couldn't read this WhatsApp export.");
    }
  }

  Future<void> _createRequest() async {
    final parsed = _parsed;
    if (parsed == null || !_mappingIsValid(parsed)) return;
    await _run(() async {
      await ref
          .read(chatImportRepositoryProvider)
          .createRequest(
            relationshipId: widget.conversation.relationshipId,
            policyVersion: _policyVersion,
            parsed: parsed,
          );
      await _reload();
    });
  }

  Future<void> _respond(ChatImportRequest request, bool approve) async {
    await _run(() async {
      await ref
          .read(chatImportRepositoryProvider)
          .respond(
            requestId: request.id,
            policyVersion: request.policyVersion,
            approve: approve,
          );
      await _reload();
    });
  }

  Future<void> _upload(ChatImportRequest request) async {
    final parsed = _parsed;
    if (parsed == null || !_mappingIsValid(parsed)) return;
    if (parsed.fingerprint != request.fileFingerprint) {
      _showError('Choose the same export that both partners approved.');
      return;
    }
    await _run(() async {
      await ref
          .read(chatImportRepositoryProvider)
          .uploadParsedMessages(
            requestId: request.id,
            parsed: parsed,
            senderMapping: _mapping,
          );
      await _reload();
    });
  }

  Future<void> _delete(ChatImportJob job) async {
    await _run(() async {
      await ref.read(chatImportRepositoryProvider).deleteImport(job.id);
      await _reload();
    });
  }

  Future<void> _revoke(ChatImportRequest request) async {
    await _run(() async {
      await ref.read(chatImportRepositoryProvider).revokeRequest(request.id);
      await _reload();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      _showError(
        'That import action could not be completed. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  bool _mappingIsValid(ParsedChatImport parsed) {
    return _mapping.keys.toSet().containsAll(parsed.participantLabels) &&
        _mapping.values.toSet().length == 2;
  }

  void _showError(String message) {
    if (mounted) setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final activeRequests = _requests.where(
      (request) =>
          !{
            ChatImportRequestState.declined,
            ChatImportRequestState.deleted,
            ChatImportRequestState.revoked,
          }.contains(request.state),
    );
    final active = activeRequests.isEmpty ? null : activeRequests.first;
    final latestDeclined = _requests.where(
      (request) => request.state == ChatImportRequestState.declined,
    );
    final declinedInCooldown =
        latestDeclined.isNotEmpty &&
        latestDeclined.first.decidedAt != null &&
        latestDeclined.first.decidedAt!.isAfter(
          DateTime.now().subtract(const Duration(days: 7)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Import chat history')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const _DisclosureCard(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (active == null && declinedInCooldown)
                    const _StatusCard(
                      title: 'Import not proceeding',
                      body:
                          'Your partner chose not to proceed. Their reason remains private. A new request can be made after the cooldown.',
                    )
                  else if (active == null)
                    _NewImportCard(
                      parsed: _parsed,
                      mapping: _mapping,
                      currentUserId: user?.id,
                      partnerId: widget.conversation.partnerId,
                      partnerName: widget.conversation.partnerName,
                      working: _working,
                      onPick: _pickExport,
                      onMappingChanged: () => setState(() {}),
                      onRequest: _createRequest,
                    )
                  else if (active.state ==
                      ChatImportRequestState.pendingPartnerConsent)
                    active.approverId == user?.id
                        ? _DecisionCard(
                          working: _working,
                          onApprove: () => _respond(active, true),
                          onDecline: () => _respond(active, false),
                        )
                        : const _StatusCard(
                          title: 'Waiting for your partner',
                          body:
                              'They can approve or decline privately. There is no automatic approval.',
                        )
                  else if (active.state == ChatImportRequestState.approved ||
                      active.state == ChatImportRequestState.failed)
                    active.uploaderId == user?.id
                        ? _ApprovedUploadCard(
                          parsed: _parsed,
                          mapping: _mapping,
                          currentUserId: user?.id,
                          partnerId: widget.conversation.partnerId,
                          partnerName: widget.conversation.partnerName,
                          working: _working,
                          onPick: _pickExport,
                          onMappingChanged: () => setState(() {}),
                          onUpload: () => _upload(active),
                        )
                        : const _StatusCard(
                          title: 'Import approved',
                          body:
                              'Your partner can now reselect the approved export and begin the import.',
                        )
                  else
                    _ProcessingStatusCard(
                      completed:
                          active.state == ChatImportRequestState.completed,
                      safetyProcessing:
                          active.state ==
                          ChatImportRequestState.processingSafety,
                      working: _working,
                      onRevoke: () => _revoke(active),
                    ),
                  if (_jobs.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Imported history',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    ..._jobs.map(
                      (job) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${job.importedCount} of ${job.expectedCount} messages',
                        ),
                        subtitle: Text(job.state.replaceAll('_', ' ')),
                        trailing:
                            job.state == 'deleted'
                                ? null
                                : TextButton(
                                  onPressed:
                                      _working ? null : () => _delete(job),
                                  child: const Text('Delete'),
                                ),
                      ),
                    ),
                  ],
                ],
              ),
    );
  }
}

class _DisclosureCard extends StatelessWidget {
  const _DisclosureCard();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Before either of you agrees',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          const Text(
            'Messages will be added with their original dates. Both partners’ words will be checked by the same relationship-intelligence and Safety systems used for new Attune messages. A historical safety match may surface a generic resource notification today. Imported evidence is labeled and receives reduced interpretive confidence. Either partner may decline privately or delete the imported history later.',
          ),
        ],
      ),
    ),
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.title, required this.body});
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) =>
      Card(child: ListTile(title: Text(title), subtitle: Text(body)));
}

class _ProcessingStatusCard extends StatelessWidget {
  const _ProcessingStatusCard({
    required this.completed,
    required this.safetyProcessing,
    required this.working,
    required this.onRevoke,
  });
  final bool completed;
  final bool safetyProcessing;
  final bool working;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            completed ? 'Import complete' : 'Import in progress',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            safetyProcessing
                ? 'Messages are imported. Safety checks must finish before completion.'
                : completed
                ? 'The imported messages are now part of this relationship chat.'
                : 'The import is being processed safely.',
          ),
          if (!completed) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: working ? null : onRevoke,
              child: const Text('Revoke consent and remove imported data'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({
    required this.working,
    required this.onApprove,
    required this.onDecline,
  });
  final bool working;
  final VoidCallback onApprove;
  final VoidCallback onDecline;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your decision', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'No message content is shown before you decide. Declining shares no reason.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: working ? null : onApprove,
            child: const Text('Approve import'),
          ),
          TextButton(
            onPressed: working ? null : onDecline,
            child: const Text('Decline'),
          ),
        ],
      ),
    ),
  );
}

class _NewImportCard extends StatelessWidget {
  const _NewImportCard({
    required this.parsed,
    required this.mapping,
    required this.currentUserId,
    required this.partnerId,
    required this.partnerName,
    required this.working,
    required this.onPick,
    required this.onMappingChanged,
    required this.onRequest,
  });
  final ParsedChatImport? parsed;
  final Map<String, String> mapping;
  final String? currentUserId;
  final String partnerId;
  final String partnerName;
  final bool working;
  final VoidCallback onPick;
  final VoidCallback onMappingChanged;
  final VoidCallback onRequest;
  @override
  Widget build(BuildContext context) => _MappingCard(
    title: 'Choose a WhatsApp export',
    parsed: parsed,
    mapping: mapping,
    currentUserId: currentUserId,
    partnerId: partnerId,
    partnerName: partnerName,
    working: working,
    onPick: onPick,
    onMappingChanged: onMappingChanged,
    actionLabel: 'Request partner consent',
    onAction: onRequest,
  );
}

class _ApprovedUploadCard extends StatelessWidget {
  const _ApprovedUploadCard({
    required this.parsed,
    required this.mapping,
    required this.currentUserId,
    required this.partnerId,
    required this.partnerName,
    required this.working,
    required this.onPick,
    required this.onMappingChanged,
    required this.onUpload,
  });
  final ParsedChatImport? parsed;
  final Map<String, String> mapping;
  final String? currentUserId;
  final String partnerId;
  final String partnerName;
  final bool working;
  final VoidCallback onPick;
  final VoidCallback onMappingChanged;
  final VoidCallback onUpload;
  @override
  Widget build(BuildContext context) => _MappingCard(
    title: 'Consent received',
    parsed: parsed,
    mapping: mapping,
    currentUserId: currentUserId,
    partnerId: partnerId,
    partnerName: partnerName,
    working: working,
    onPick: onPick,
    onMappingChanged: onMappingChanged,
    actionLabel: 'Begin import',
    onAction: onUpload,
  );
}

class _MappingCard extends StatelessWidget {
  const _MappingCard({
    required this.title,
    required this.parsed,
    required this.mapping,
    required this.currentUserId,
    required this.partnerId,
    required this.partnerName,
    required this.working,
    required this.onPick,
    required this.onMappingChanged,
    required this.actionLabel,
    required this.onAction,
  });
  final String title;
  final ParsedChatImport? parsed;
  final Map<String, String> mapping;
  final String? currentUserId;
  final String partnerId;
  final String partnerName;
  final bool working;
  final VoidCallback onPick;
  final VoidCallback onMappingChanged;
  final String actionLabel;
  final VoidCallback onAction;
  @override
  Widget build(BuildContext context) {
    final mappingConfirmed =
        parsed != null &&
        mapping.keys.toSet().containsAll(parsed!.participantLabels) &&
        mapping.values.toSet().length == 2;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: working ? null : onPick,
              child: Text(
                parsed == null
                    ? 'Select .txt or .zip'
                    : 'Choose a different export',
              ),
            ),
            if (parsed != null) ...[
              const SizedBox(height: 12),
              Text(
                '${parsed!.messages.length} text messages • ${parsed!.firstMessageAt.toLocal().toString().split(' ').first} to ${parsed!.lastMessageAt.toLocal().toString().split(' ').first}',
              ),
              const SizedBox(height: 12),
              ...parsed!.participantLabels.map(
                (label) => DropdownButtonFormField<String>(
                  value: mapping[label],
                  decoration: InputDecoration(labelText: '“$label” is'),
                  items: [
                    DropdownMenuItem(
                      value: currentUserId,
                      child: const Text('Me'),
                    ),
                    DropdownMenuItem(
                      value: partnerId,
                      child: Text(partnerName),
                    ),
                  ],
                  onChanged:
                      working
                          ? null
                          : (value) {
                            if (value != null) mapping[label] = value;
                            onMappingChanged();
                          },
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: working || !mappingConfirmed ? null : onAction,
                child: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
