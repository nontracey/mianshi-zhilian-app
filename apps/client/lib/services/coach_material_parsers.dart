/// App assembly: use the selected model for source-aligned drafts and retain
/// deterministic offline parsing when its configuration or service is unavailable.
library;

import '../coach/application/coach_agent.dart';
import '../coach/jobs/jd_import_service.dart';
import '../coach/resume/resume_parse.dart';

class ConfiguredJdParser implements JdParser {
  const ConfiguredJdParser(this.bindingProvider);
  final CoachModelBindingProvider bindingProvider;
  @override
  Future<JdParseResult> parse(String text, {String? url, String? title}) async {
    final binding = bindingProvider();
    if (binding != null) {
      try {
        final caps = await binding.capabilities();
        final result = await ModelJdParser(
          binding.gateway,
          responseFormatJson: caps.supportsJsonResponse,
        ).parse(text, url: url, title: title);
        final requirements = result.requirements
            .where((r) => r.statement.trim().isNotEmpty)
            .take(50)
            .map((r) {
              final anchored =
                  r.jdSourceSpan?.trim().isNotEmpty == true &&
                  text.contains(r.jdSourceSpan!);
              return RequirementDraft(
                statement: r.statement,
                type: r.type,
                importance: r.importance,
                jdSourceSpan: anchored ? r.jdSourceSpan : null,
                inferred: r.inferred || !anchored,
                inferenceRationale: r.inferred || !anchored
                    ? 'Model draft; confirm against the original JD.'
                    : null,
              );
            })
            .toList();
        return JdParseResult(
          title: title ?? result.title,
          company: result.company,
          location: result.location,
          salaryText: result.salaryText,
          description: result.description,
          requirements: requirements,
        );
      } catch (_) {
        /* Offline extraction remains a visibly inferred draft. */
      }
    }
    return const HeuristicJdParser().parse(text, url: url, title: title);
  }
}

class ConfiguredResumeParser implements ResumeParser {
  const ConfiguredResumeParser(this.bindingProvider);
  final CoachModelBindingProvider bindingProvider;
  @override
  Future<ResumeParseResult> parse(String text, {String? fileName}) async {
    final binding = bindingProvider();
    if (binding != null) {
      try {
        final caps = await binding.capabilities();
        final result = await ModelResumeParser(
          binding.gateway,
          responseFormatJson: caps.supportsJsonResponse,
        ).parse(text, fileName: fileName);
        bool anchored(String? span) =>
            span?.trim().isNotEmpty == true && text.contains(span!);
        String? literal(String? value, String span) =>
            value != null && span.contains(value) ? value : null;
        final projects = result.projects
            .where((p) => anchored(p.originalSpan))
            .take(50)
            .map(
              (p) => ProjectDraft(
                name: p.name,
                originalSpan: p.originalSpan,
                goal: literal(p.goal, p.originalSpan!),
                responsibilities: literal(p.responsibilities, p.originalSpan!),
                techStack: literal(p.techStack, p.originalSpan!),
                metrics: literal(p.metrics, p.originalSpan!),
                timeRange: literal(p.timeRange, p.originalSpan!),
              ),
            )
            .toList();
        final names = projects.map((p) => p.name).toSet();
        final claims = result.claims
            .where(
              (c) => anchored(c.originalSpan) && c.statement.trim().isNotEmpty,
            )
            .take(100)
            .map(
              (c) => ClaimDraft(
                statement: c.statement,
                originalSpan: c.originalSpan,
                projectName: names.contains(c.projectName)
                    ? c.projectName
                    : null,
                confidence: c.confidence?.clamp(0, 1).toDouble(),
                type: c.type,
              ),
            )
            .toList();
        if (projects.isNotEmpty || claims.isNotEmpty)
          return ResumeParseResult(
            fields: result.fields,
            projects: projects,
            claims: claims,
            parseNotes: const [
              'Model drafts require confirmation against the preserved original text.',
            ],
          );
      } catch (_) {
        /* Never manufacture a project after a failed model request. */
      }
    }
    return const RuleBasedResumeParser().parse(text, fileName: fileName);
  }
}
