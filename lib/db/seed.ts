import bcrypt from "bcryptjs";
import { sql } from "drizzle-orm";
import type { PgDatabase, PgQueryResultHKT } from "drizzle-orm/pg-core";
import * as schema from "./schema";
import { DEMO_PASSWORD, demoUsers, seedRecipes } from "./seed-data";

type AnyDb = PgDatabase<PgQueryResultHKT, typeof schema>;

/** Idempotent: safe to run against a database that is already seeded. */
export async function seed(db: AnyDb) {
  const passwordHash = await bcrypt.hash(DEMO_PASSWORD, 10);

  await db.transaction(async (tx) => {
    for (const u of demoUsers) {
      await tx
        .insert(schema.users)
        .values({ ...u, passwordHash })
        .onConflictDoUpdate({
          target: schema.users.email,
          set: { fullName: u.fullName, role: u.role, passwordHash },
        });
    }

    for (const { components, ...recipe } of seedRecipes) {
      const [row] = await tx
        .insert(schema.recipes)
        .values(recipe)
        .onConflictDoUpdate({
          target: schema.recipes.recipeCode,
          set: {
            name: recipe.name,
            category: recipe.category,
            stdFabricYards: recipe.stdFabricYards,
            wastageCap: recipe.wastageCap,
          },
        })
        .returning({ id: schema.recipes.id });

      await tx
        .insert(schema.recipeComponents)
        .values(components.map((c, i) => ({ ...c, recipeId: row.id, sortOrder: i })))
        .onConflictDoUpdate({
          target: [schema.recipeComponents.recipeId, schema.recipeComponents.componentName],
          set: {
            piecesPerGarment: sql`excluded.pieces_per_garment`,
            sortOrder: sql`excluded.sort_order`,
          },
        });
    }
  });
}
