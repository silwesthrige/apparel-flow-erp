CREATE TYPE "public"."verification_decision" AS ENUM('APPROVED', 'REJECTED');--> statement-breakpoint
CREATE TYPE "public"."order_status" AS ENUM('CUTTING_IN_PROGRESS', 'PENDING_VERIFICATION', 'REJECTED', 'VERIFIED', 'IN_SEWING');--> statement-breakpoint
CREATE TYPE "public"."role" AS ENUM('cutting_supervisor', 'cutting_verifier', 'sewing_supervisor');--> statement-breakpoint
CREATE TABLE "cutting_orders" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"order_seq" integer GENERATED ALWAYS AS IDENTITY (sequence name "cutting_orders_order_seq_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 2147483647 START WITH 1 CACHE 1),
	"order_no" text GENERATED ALWAYS AS ('CO-' || lpad(order_seq::text, 5, '0')) STORED NOT NULL,
	"recipe_id" uuid NOT NULL,
	"target_qty" integer NOT NULL,
	"fabric_roll_id" text NOT NULL,
	"actual_fabric_yds" numeric(10, 2) NOT NULL,
	"expected_fabric_yds" numeric(10, 2) NOT NULL,
	"status" "order_status" DEFAULT 'CUTTING_IN_PROGRESS' NOT NULL,
	"created_by" uuid NOT NULL,
	"wastage_pct" numeric(7, 2),
	"verified_by" uuid,
	"verified_at" timestamp with time zone,
	"sewing_started_by" uuid,
	"sewing_started_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "cutting_orders_order_no_uq" UNIQUE("order_no"),
	CONSTRAINT "cutting_orders_target_qty_positive" CHECK ("cutting_orders"."target_qty" > 0),
	CONSTRAINT "cutting_orders_actual_fabric_positive" CHECK ("cutting_orders"."actual_fabric_yds" > 0),
	CONSTRAINT "cutting_orders_expected_fabric_positive" CHECK ("cutting_orders"."expected_fabric_yds" > 0),
	CONSTRAINT "cutting_orders_verified_audit_present" CHECK ("cutting_orders"."status" NOT IN ('VERIFIED', 'IN_SEWING')
          OR ("cutting_orders"."verified_by" IS NOT NULL AND "cutting_orders"."verified_at" IS NOT NULL AND "cutting_orders"."wastage_pct" IS NOT NULL))
);
--> statement-breakpoint
CREATE TABLE "recipe_components" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"recipe_id" uuid NOT NULL,
	"component_name" text NOT NULL,
	"pieces_per_garment" integer NOT NULL,
	"image_url" text,
	"sort_order" integer DEFAULT 0 NOT NULL,
	CONSTRAINT "recipe_components_recipe_name_uq" UNIQUE("recipe_id","component_name"),
	CONSTRAINT "recipe_components_pieces_positive" CHECK ("recipe_components"."pieces_per_garment" > 0)
);
--> statement-breakpoint
CREATE TABLE "recipes" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"recipe_code" text NOT NULL,
	"name" text NOT NULL,
	"category" text NOT NULL,
	"std_fabric_yards" numeric(6, 2) NOT NULL,
	"wastage_cap" numeric(5, 2) NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "recipes_recipeCode_unique" UNIQUE("recipe_code"),
	CONSTRAINT "recipes_std_fabric_positive" CHECK ("recipes"."std_fabric_yards" > 0),
	CONSTRAINT "recipes_wastage_cap_range" CHECK ("recipes"."wastage_cap" >= 0 AND "recipes"."wastage_cap" <= 100)
);
--> statement-breakpoint
CREATE TABLE "users" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"email" text NOT NULL,
	"password_hash" text NOT NULL,
	"role" "role" NOT NULL,
	"full_name" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "users_email_unique" UNIQUE("email")
);
--> statement-breakpoint
CREATE TABLE "verification_items" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"order_id" uuid NOT NULL,
	"component_id" uuid NOT NULL,
	"expected_qty" integer NOT NULL,
	"actual_qty" integer,
	"status" text GENERATED ALWAYS AS (CASE
            WHEN actual_qty IS NULL THEN NULL
            WHEN actual_qty = expected_qty THEN 'GREEN'
            WHEN actual_qty > expected_qty THEN 'YELLOW'
            ELSE 'RED'
          END) STORED,
	CONSTRAINT "verification_items_order_component_uq" UNIQUE("order_id","component_id"),
	CONSTRAINT "verification_items_expected_positive" CHECK ("verification_items"."expected_qty" > 0),
	CONSTRAINT "verification_items_actual_non_negative" CHECK ("verification_items"."actual_qty" IS NULL OR "verification_items"."actual_qty" >= 0)
);
--> statement-breakpoint
CREATE TABLE "verification_logs" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"order_id" uuid NOT NULL,
	"verifier_id" uuid NOT NULL,
	"decision" "verification_decision" NOT NULL,
	"rejection_note" text,
	"wastage_pct" numeric(7, 2) NOT NULL,
	"component_snapshot" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "verification_logs_rejection_note_required" CHECK ("verification_logs"."decision" = 'APPROVED' OR length(btrim(coalesce("verification_logs"."rejection_note", ''))) >= 10)
);
--> statement-breakpoint
ALTER TABLE "cutting_orders" ADD CONSTRAINT "cutting_orders_recipe_id_recipes_id_fk" FOREIGN KEY ("recipe_id") REFERENCES "public"."recipes"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "cutting_orders" ADD CONSTRAINT "cutting_orders_created_by_users_id_fk" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "cutting_orders" ADD CONSTRAINT "cutting_orders_verified_by_users_id_fk" FOREIGN KEY ("verified_by") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "cutting_orders" ADD CONSTRAINT "cutting_orders_sewing_started_by_users_id_fk" FOREIGN KEY ("sewing_started_by") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recipe_components" ADD CONSTRAINT "recipe_components_recipe_id_recipes_id_fk" FOREIGN KEY ("recipe_id") REFERENCES "public"."recipes"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "verification_items" ADD CONSTRAINT "verification_items_order_id_cutting_orders_id_fk" FOREIGN KEY ("order_id") REFERENCES "public"."cutting_orders"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "verification_items" ADD CONSTRAINT "verification_items_component_id_recipe_components_id_fk" FOREIGN KEY ("component_id") REFERENCES "public"."recipe_components"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "verification_logs" ADD CONSTRAINT "verification_logs_order_id_cutting_orders_id_fk" FOREIGN KEY ("order_id") REFERENCES "public"."cutting_orders"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "verification_logs" ADD CONSTRAINT "verification_logs_verifier_id_users_id_fk" FOREIGN KEY ("verifier_id") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "cutting_orders_status_idx" ON "cutting_orders" USING btree ("status");--> statement-breakpoint
CREATE INDEX "verification_logs_order_idx" ON "verification_logs" USING btree ("order_id");