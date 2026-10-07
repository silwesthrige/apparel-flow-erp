-- Database-level integrity guards. The service layer enforces these rules too; the
-- triggers make them hold even for a buggy service or a direct SQL session.

-- 1. State machine + hard stop + audit immutability on cutting_orders.
CREATE OR REPLACE FUNCTION enforce_cutting_order_rules() RETURNS trigger AS $$
DECLARE
  bad_items integer;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'cutting_orders rows cannot be deleted (order %)', OLD.order_no
      USING ERRCODE = 'restrict_violation';
  END IF;

  -- Audit fields are write-once: set only by the VERIFIED / IN_SEWING transitions.
  IF OLD.status IN ('VERIFIED', 'IN_SEWING') THEN
    IF NEW.recipe_id IS DISTINCT FROM OLD.recipe_id
       OR NEW.target_qty IS DISTINCT FROM OLD.target_qty
       OR NEW.fabric_roll_id IS DISTINCT FROM OLD.fabric_roll_id
       OR NEW.actual_fabric_yds IS DISTINCT FROM OLD.actual_fabric_yds
       OR NEW.expected_fabric_yds IS DISTINCT FROM OLD.expected_fabric_yds
       OR NEW.wastage_pct IS DISTINCT FROM OLD.wastage_pct
       OR NEW.verified_by IS DISTINCT FROM OLD.verified_by
       OR NEW.verified_at IS DISTINCT FROM OLD.verified_at
       OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
      RAISE EXCEPTION 'order % is verified; its audit fields are immutable', OLD.order_no
        USING ERRCODE = 'integrity_constraint_violation';
    END IF;
  END IF;

  IF OLD.status = 'IN_SEWING' AND (
       NEW.sewing_started_by IS DISTINCT FROM OLD.sewing_started_by
       OR NEW.sewing_started_at IS DISTINCT FROM OLD.sewing_started_at) THEN
    RAISE EXCEPTION 'order % sewing attribution is immutable', OLD.order_no
      USING ERRCODE = 'integrity_constraint_violation';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT (
         (OLD.status = 'CUTTING_IN_PROGRESS'  AND NEW.status = 'PENDING_VERIFICATION')
      OR (OLD.status = 'PENDING_VERIFICATION' AND NEW.status IN ('VERIFIED', 'REJECTED'))
      OR (OLD.status = 'REJECTED'             AND NEW.status = 'CUTTING_IN_PROGRESS')
      OR (OLD.status = 'VERIFIED'             AND NEW.status = 'IN_SEWING')
    ) THEN
      RAISE EXCEPTION 'illegal status transition % -> % for order %', OLD.status, NEW.status, OLD.order_no
        USING ERRCODE = 'check_violation';
    END IF;

    -- Hard stop: no batch is VERIFIED while any component is short or uncounted.
    IF NEW.status = 'VERIFIED' THEN
      SELECT count(*) INTO bad_items
        FROM verification_items
       WHERE order_id = NEW.id
         AND (status IS NULL OR status = 'RED');
      IF bad_items > 0 THEN
        RAISE EXCEPTION 'order % has % short or uncounted component(s); cannot verify', OLD.order_no, bad_items
          USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
--> statement-breakpoint
CREATE TRIGGER cutting_orders_rules
  BEFORE UPDATE OR DELETE ON cutting_orders
  FOR EACH ROW EXECUTE FUNCTION enforce_cutting_order_rules();
--> statement-breakpoint

-- 2. Counts are frozen once the order leaves PENDING_VERIFICATION / CUTTING_IN_PROGRESS.
CREATE OR REPLACE FUNCTION enforce_verification_item_rules() RETURNS trigger AS $$
DECLARE
  order_status order_status;
BEGIN
  SELECT status INTO order_status FROM cutting_orders
   WHERE id = COALESCE(NEW.order_id, OLD.order_id);

  IF order_status IN ('VERIFIED', 'IN_SEWING') THEN
    RAISE EXCEPTION 'verification items of a verified order are immutable'
      USING ERRCODE = 'integrity_constraint_violation';
  END IF;

  IF TG_OP = 'UPDATE' AND (
       NEW.expected_qty IS DISTINCT FROM OLD.expected_qty
       OR NEW.order_id IS DISTINCT FROM OLD.order_id
       OR NEW.component_id IS DISTINCT FROM OLD.component_id) THEN
    RAISE EXCEPTION 'expected quantities are fixed at order creation'
      USING ERRCODE = 'integrity_constraint_violation';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
--> statement-breakpoint
CREATE TRIGGER verification_items_rules
  BEFORE UPDATE OR DELETE ON verification_items
  FOR EACH ROW EXECUTE FUNCTION enforce_verification_item_rules();
--> statement-breakpoint

-- 3. The verification log is append-only.
CREATE OR REPLACE FUNCTION forbid_verification_log_mutation() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'verification_logs is append-only'
    USING ERRCODE = 'integrity_constraint_violation';
END;
$$ LANGUAGE plpgsql;
--> statement-breakpoint
CREATE TRIGGER verification_logs_append_only
  BEFORE UPDATE OR DELETE ON verification_logs
  FOR EACH ROW EXECUTE FUNCTION forbid_verification_log_mutation();
--> statement-breakpoint
-- TRUNCATE bypasses row triggers, so block it explicitly.
CREATE TRIGGER verification_logs_no_truncate
  BEFORE TRUNCATE ON verification_logs
  FOR EACH STATEMENT EXECUTE FUNCTION forbid_verification_log_mutation();
