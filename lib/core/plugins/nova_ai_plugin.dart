import 'drawing_plugin.dart';

/// First NOVA adapter contract. Providers receive only explicitly supplied input;
/// generation returns a proposal and never changes an editor document directly.
abstract interface class NovaAiPlugin implements DrawingPlugin {
  Future<NovaAiProposal> generate(NovaAiRequest request);
}

final class NovaAiRequest {
  NovaAiRequest({required this.prompt, List<String> references = const []})
    : references = List<String>.unmodifiable(references);

  final String prompt;
  final List<String> references;
}

/// Generated text and artifact references are reviewed by the calling workflow.
/// Artifact loading and undoable document insertion belong to the host adapter.
final class NovaAiProposal {
  NovaAiProposal({required this.text, List<String> artifacts = const []})
    : artifacts = List<String>.unmodifiable(artifacts);

  final String text;
  final List<String> artifacts;
}
