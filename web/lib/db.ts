import { Pool, types, DatabaseError } from "pg";

// TIMESTAMP and DATE stay strings: as JS Dates they would be shifted into
// the Node process's timezone, but the database stores them without one.
types.setTypeParser(types.builtins.TIMESTAMP, (v) => v);
types.setTypeParser(types.builtins.DATE, (v) => v);
types.setTypeParser(types.builtins.NUMERIC, (v) => parseFloat(v));
types.setTypeParser(types.builtins.INT8, (v) => parseInt(v, 10));

const globalForPg = globalThis as unknown as { pgPool?: Pool };

export function getPool(): Pool {
  if (!globalForPg.pgPool) {
    const connectionString = process.env.DATABASE_URL;
    if (!connectionString) throw new Error("DATABASE_URL is not set. Copy web/.env.example to web/.env.");
    globalForPg.pgPool = new Pool({ connectionString });
  }
  return globalForPg.pgPool;
}

export function dbErrorMessage(err: unknown): string {
  if (err instanceof DatabaseError) return err.detail ? `${err.message}. ${err.detail}` : err.message;
  return err instanceof Error ? err.message : "Unexpected error";
}
