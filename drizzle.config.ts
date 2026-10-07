import "dotenv/config";
import { defineConfig } from "drizzle-kit";

export default defineConfig({
  schema: "./lib/db/schema.ts",
  out: "./drizzle",
  dialect: "postgresql",
  casing: "snake_case",
  dbCredentials: {
    // Migrations need a session-mode connection (Supabase direct / session pooler, port 5432).
    url: process.env.DIRECT_URL ?? process.env.DATABASE_URL!,
  },
});
