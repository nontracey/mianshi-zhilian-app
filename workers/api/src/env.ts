export interface Env {
  CONTENT_PRIMARY_BASE_URL?: string;
  CONTENT_BACKUP_BASE_URL?: string;
  DB: D1Database;
  JWT_SECRET: string;
  KV: KVNamespace;
}
