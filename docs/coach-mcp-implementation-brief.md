# MCP V1 implementation brief

> Target design, not current support. Re-audit 2026-09-12: only the 2025-11-25 reader subset is exposed; 2026-07-28, OAuth and coach retrieval integration remain pending. See [current audit](coach-implementation-audit.md).

Required versions: 2026-07-28 and 2025-11-25. Root inspected official specification on 2026-09-11. Implement read-only HTTP subset, explicit per-service/tool/scope grants, isolated credentials, bounded results, timeout/cancel, local JSON/SSE contract tests. Do not claim all MCP capabilities.

2026-07-28: request-specific POST; no initialize/session/GET legacy lifecycle. Every request mirrors method in Mcp-Method, name/URI in Mcp-Name and version in MCP-Protocol-Version. Body params._meta carries io.modelcontextprotocol/protocolVersion, clientInfo, clientCapabilities. Support ASCII/Base64 sentinel header encoding and primitive x-mcp-header annotations (strict validation). JSON or request-scoped SSE ends at matching response. Closing response stream cancels; server input requests are not autonomous instructions.

2025-11-25: initialize negotiation, initialized notification, session header lifecycle and version header; handle JSON/SSE response and mismatching IDs. Neither version may allow remote prompts, sampling, elicitation or shell execution to become implicit permissions.

Protected services: OAuth metadata discovery, authorization code with PKCE/state, scoped tokens/refresh, origin-bound credential storage; static bearer support is only one auth option. No tokens in URLs, exports, logs or model prompts. Use the application credential abstraction and caller-provided callback configuration.

Sources:
- https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http
- https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization
- https://modelcontextprotocol.io/specification/2025-11-25/basic/transports

Before implementation read the exact official sections, including header encoding and OAuth requirements. Root brief is not a replacement for protocol details.
