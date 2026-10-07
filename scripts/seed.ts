import "dotenv/config";
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "../lib/db/schema";
import { seed } from "../lib/db/seed";

const url = process.env.DIRECT_URL ?? process.env.DATABASE_URL;
if (!url) throw new Error("DIRECT_URL or DATABASE_URL must be set");

const client = postgres(url, { prepare: false, max: 1 });
await seed(drizzle(client, { schema, casing: "snake_case" }));
await client.end();
console.log("Seed complete: 3 demo users, 2 recipes.");
