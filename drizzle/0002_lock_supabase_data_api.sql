-- Supabase exposes the public schema through its REST Data API (PostgREST) to the anon and
-- authenticated roles. This app never uses that API: all access goes through our Next.js
-- route handlers, which enforce RBAC. Enabling RLS with no policies denies those roles every
-- row, closing the bypass. The app connects as the table owner, which RLS does not restrict.
ALTER TABLE users ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE recipes ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE recipe_components ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE cutting_orders ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE verification_items ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE verification_logs ENABLE ROW LEVEL SECURITY;
