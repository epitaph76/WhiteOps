import { Pool } from "pg";

import { PersistedGraphStoreSnapshot } from "./graph-store";

function quoteIdentifierChain(input: string): string {
  const trimmed = input.trim();
  if (!trimmed) {
    throw new Error("Postgres snapshot table name cannot be empty");
  }

  const parts = trimmed.split(".").map((part) => part.trim()).filter(Boolean);
  if (parts.length === 0) {
    throw new Error("Postgres snapshot table name cannot be empty");
  }

  for (const part of parts) {
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(part)) {
      throw new Error(
        `Invalid postgres identifier '${part}' in table '${input}'. Use only letters, digits and underscore.`,
      );
    }
  }

  return parts.map((part) => `"${part}"`).join(".");
}

export class PgSnapshotStore {
  private readonly pool: Pool;
  private readonly tableName: string;
  private readonly quotedTableName: string;

  constructor(connectionString: string, tableName: string) {
    this.pool = new Pool({
      connectionString,
      max: 5,
    });
    this.tableName = tableName.trim();
    this.quotedTableName = quoteIdentifierChain(this.tableName);
  }

  async initialize(): Promise<void> {
    await this.pool.query(`
      CREATE TABLE IF NOT EXISTS ${this.quotedTableName} (
        id SMALLINT PRIMARY KEY,
        version INTEGER NOT NULL,
        saved_at TIMESTAMPTZ NOT NULL,
        snapshot JSONB NOT NULL
      )
    `);
  }

  async load(): Promise<PersistedGraphStoreSnapshot | undefined> {
    const result = await this.pool.query(
      `SELECT snapshot FROM ${this.quotedTableName} WHERE id = 1`,
    );
    if (result.rowCount === 0) {
      return undefined;
    }

    const raw = result.rows[0]?.snapshot;
    if (!raw || typeof raw !== "object") {
      return undefined;
    }

    return raw as PersistedGraphStoreSnapshot;
  }

  async save(snapshot: PersistedGraphStoreSnapshot): Promise<void> {
    await this.pool.query(
      `
      INSERT INTO ${this.quotedTableName} (id, version, saved_at, snapshot)
      VALUES (1, $1, $2, $3::jsonb)
      ON CONFLICT (id)
      DO UPDATE SET
        version = EXCLUDED.version,
        saved_at = EXCLUDED.saved_at,
        snapshot = EXCLUDED.snapshot
      `,
      [snapshot.version, snapshot.savedAt, JSON.stringify(snapshot)],
    );
  }

  async close(): Promise<void> {
    await this.pool.end();
  }
}
