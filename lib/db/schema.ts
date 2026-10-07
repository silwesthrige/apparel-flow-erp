import { sql } from "drizzle-orm";
import {
  check,
  index,
  integer,
  jsonb,
  numeric,
  pgEnum,
  pgTable,
  text,
  timestamp,
  unique,
  uuid,
} from "drizzle-orm/pg-core";

export const roleEnum = pgEnum("role", [
  "cutting_supervisor",
  "cutting_verifier",
  "sewing_supervisor",
]);

export const orderStatusEnum = pgEnum("order_status", [
  "CUTTING_IN_PROGRESS",
  "PENDING_VERIFICATION",
  "REJECTED",
  "VERIFIED",
  "IN_SEWING",
]);

export const decisionEnum = pgEnum("verification_decision", [
  "APPROVED",
  "REJECTED",
]);

export const users = pgTable("users", {
  id: uuid().primaryKey().defaultRandom(),
  email: text().notNull().unique(),
  passwordHash: text().notNull(),
  role: roleEnum().notNull(),
  fullName: text().notNull(),
  createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
});

export const recipes = pgTable(
  "recipes",
  {
    id: uuid().primaryKey().defaultRandom(),
    recipeCode: text().notNull().unique(),
    name: text().notNull(),
    category: text().notNull(),
    // numeric, not float: fabric is money-like and must not drift (0.1 + 0.2 problem).
    stdFabricYards: numeric({ precision: 6, scale: 2 }).notNull(),
    wastageCap: numeric({ precision: 5, scale: 2 }).notNull(),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    check("recipes_std_fabric_positive", sql`${t.stdFabricYards} > 0`),
    check("recipes_wastage_cap_range", sql`${t.wastageCap} >= 0 AND ${t.wastageCap} <= 100`),
  ],
);

export const recipeComponents = pgTable(
  "recipe_components",
  {
    id: uuid().primaryKey().defaultRandom(),
    recipeId: uuid()
      .notNull()
      .references(() => recipes.id, { onDelete: "restrict" }),
    componentName: text().notNull(),
    piecesPerGarment: integer().notNull(),
    imageUrl: text(),
    sortOrder: integer().notNull().default(0),
  },
  (t) => [
    unique("recipe_components_recipe_name_uq").on(t.recipeId, t.componentName),
    check("recipe_components_pieces_positive", sql`${t.piecesPerGarment} > 0`),
  ],
);

export const cuttingOrders = pgTable(
  "cutting_orders",
  {
    id: uuid().primaryKey().defaultRandom(),
    orderSeq: integer().generatedAlwaysAsIdentity(),
    // Human-readable number derived from the identity, e.g. CO-00042. Never client-supplied.
    orderNo: text()
      .notNull()
      .generatedAlwaysAs(sql`'CO-' || lpad(order_seq::text, 5, '0')`),
    recipeId: uuid()
      .notNull()
      .references(() => recipes.id, { onDelete: "restrict" }),
    targetQty: integer().notNull(),
    fabricRollId: text().notNull(),
    actualFabricYds: numeric({ precision: 10, scale: 2 }).notNull(),
    // Snapshot of target_qty × recipe.std_fabric_yards at creation, so later recipe edits
    // cannot retroactively change an order's wastage.
    expectedFabricYds: numeric({ precision: 10, scale: 2 }).notNull(),
    status: orderStatusEnum().notNull().default("CUTTING_IN_PROGRESS"),
    createdBy: uuid()
      .notNull()
      .references(() => users.id),
    // Audit fields written once on approval; locked by trigger afterwards.
    wastagePct: numeric({ precision: 7, scale: 2 }),
    verifiedBy: uuid().references(() => users.id),
    verifiedAt: timestamp({ withTimezone: true }),
    sewingStartedBy: uuid().references(() => users.id),
    sewingStartedAt: timestamp({ withTimezone: true }),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    unique("cutting_orders_order_no_uq").on(t.orderNo),
    index("cutting_orders_status_idx").on(t.status),
    check("cutting_orders_target_qty_positive", sql`${t.targetQty} > 0`),
    check("cutting_orders_actual_fabric_positive", sql`${t.actualFabricYds} > 0`),
    check("cutting_orders_expected_fabric_positive", sql`${t.expectedFabricYds} > 0`),
    check(
      "cutting_orders_verified_audit_present",
      sql`${t.status} NOT IN ('VERIFIED', 'IN_SEWING')
          OR (${t.verifiedBy} IS NOT NULL AND ${t.verifiedAt} IS NOT NULL AND ${t.wastagePct} IS NOT NULL)`,
    ),
  ],
);

export const verificationItems = pgTable(
  "verification_items",
  {
    id: uuid().primaryKey().defaultRandom(),
    orderId: uuid()
      .notNull()
      .references(() => cuttingOrders.id, { onDelete: "cascade" }),
    componentId: uuid()
      .notNull()
      .references(() => recipeComponents.id, { onDelete: "restrict" }),
    // Snapshot of target_qty × pieces_per_garment at order creation.
    expectedQty: integer().notNull(),
    // NULL = not yet counted by the verifier.
    actualQty: integer(),
    // Computed by Postgres, never written by application code: the traffic light
    // cannot be forged by a client or a buggy service.
    status: text().generatedAlwaysAs(
      sql`CASE
            WHEN actual_qty IS NULL THEN NULL
            WHEN actual_qty = expected_qty THEN 'GREEN'
            WHEN actual_qty > expected_qty THEN 'YELLOW'
            ELSE 'RED'
          END`,
    ),
  },
  (t) => [
    unique("verification_items_order_component_uq").on(t.orderId, t.componentId),
    check("verification_items_expected_positive", sql`${t.expectedQty} > 0`),
    check("verification_items_actual_non_negative", sql`${t.actualQty} IS NULL OR ${t.actualQty} >= 0`),
  ],
);

export const verificationLogs = pgTable(
  "verification_logs",
  {
    id: uuid().primaryKey().defaultRandom(),
    orderId: uuid()
      .notNull()
      .references(() => cuttingOrders.id, { onDelete: "restrict" }),
    verifierId: uuid()
      .notNull()
      .references(() => users.id),
    decision: decisionEnum().notNull(),
    rejectionNote: text(),
    wastagePct: numeric({ precision: 7, scale: 2 }).notNull(),
    // Per-component expected/actual/variance at the moment of decision.
    componentSnapshot: jsonb().notNull(),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    index("verification_logs_order_idx").on(t.orderId),
    check(
      "verification_logs_rejection_note_required",
      sql`${t.decision} = 'APPROVED' OR length(btrim(coalesce(${t.rejectionNote}, ''))) >= 10`,
    ),
  ],
);

export type Role = (typeof roleEnum.enumValues)[number];
export type OrderStatus = (typeof orderStatusEnum.enumValues)[number];
