import "server-only";
import { drizzle, type PostgresJsDatabase } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema";

export type Db = PostgresJsDatabase<typeof schema>;

const globalForDb = globalThis as unknown as { pgClient?: postgres.Sql };

function createClient() {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error("DATABASE_URL is not set");
  // Supabase transaction pooler (port 6543) does not support prepared statements.
  return postgres(url, { prepare: false, max: 5 });
}

// Reuse one pool across dev hot reloads instead of leaking a new one per edit.
const client = globalForDb.pgClient ?? createClient();
if (process.env.NODE_ENV !== "production") globalForDb.pgClient = client;

export const db: Db = drizzle(client, { schema, casing: "snake_case" });
