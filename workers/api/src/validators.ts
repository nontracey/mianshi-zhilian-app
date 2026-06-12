export function asString(value: unknown, max = 200): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

export function parseJsonArray(value: unknown): string[] {
  if (Array.isArray(value)) return value.map((v) => String(v)).slice(0, 5);
  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value);
      return Array.isArray(parsed)
        ? parsed.map((v) => String(v)).slice(0, 5)
        : [];
    } catch {
      return [];
    }
  }
  return [];
}

export function isUuidLike(value: string): boolean {
  return /^[a-zA-Z0-9_-]{8,80}$/.test(value);
}
