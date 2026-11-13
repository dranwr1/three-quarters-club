BEGIN;

DO $$
DECLARE
  v_book_type text;
  v_member_type text;
  v_actual_type text;
BEGIN
  SELECT data_type INTO v_book_type
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='books' AND column_name='id';
  SELECT data_type INTO v_member_type
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='members' AND column_name='id';

  IF v_book_type IS NULL OR v_member_type IS NULL
     OR v_book_type NOT IN ('uuid','bigint')
     OR v_member_type NOT IN ('uuid','bigint') THEN
    RAISE EXCEPTION
      'Book roulette requires public.books.id and public.members.id to be uuid or bigint. Found books=%, members=%.',
      COALESCE(v_book_type,'missing'), COALESCE(v_member_type,'missing');
  END IF;

  v_book_type := CASE v_book_type WHEN 'uuid' THEN 'uuid' ELSE 'bigint' END;
  v_member_type := CASE v_member_type WHEN 'uuid' THEN 'uuid' ELSE 'bigint' END;

  IF to_regclass('public.book_roulette_spins') IS NULL THEN
    EXECUTE format(
      'CREATE TABLE public.book_roulette_spins (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        selected_book_id %s NOT NULL,
        spun_by_member_id %s NOT NULL,
        status text NOT NULL DEFAULT ''selected''
          CHECK (status IN (''selected'',''vetoed'',''approved'')),
        vetoed_by_member_id %s,
        veto_reason text,
        vetoed_at timestamptz,
        created_at timestamptz NOT NULL DEFAULT now()
      )',
      v_book_type, v_member_type, v_member_type
    );
  ELSE
    SELECT data_type INTO v_actual_type
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name='book_roulette_spins'
      AND column_name='selected_book_id';
    IF v_actual_type IS DISTINCT FROM v_book_type THEN
      RAISE EXCEPTION
        'book_roulette_spins.selected_book_id type (%) does not match books.id type (%).',
        COALESCE(v_actual_type,'missing'), v_book_type;
    END IF;

    SELECT data_type INTO v_actual_type
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name='book_roulette_spins'
      AND column_name='spun_by_member_id';
    IF v_actual_type IS DISTINCT FROM v_member_type THEN
      RAISE EXCEPTION
        'book_roulette_spins.spun_by_member_id type (%) does not match members.id type (%).',
        COALESCE(v_actual_type,'missing'), v_member_type;
    END IF;

    SELECT data_type INTO v_actual_type
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name='book_roulette_spins'
      AND column_name='vetoed_by_member_id';
    IF v_actual_type IS DISTINCT FROM v_member_type THEN
      RAISE EXCEPTION
        'book_roulette_spins.vetoed_by_member_id type (%) does not match members.id type (%).',
        COALESCE(v_actual_type,'missing'), v_member_type;
    END IF;
  END IF;

  EXECUTE 'ALTER TABLE public.book_roulette_spins
    ALTER COLUMN id SET DEFAULT gen_random_uuid(),
    ALTER COLUMN status SET DEFAULT ''selected'',
    ALTER COLUMN created_at SET DEFAULT now()';

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.book_roulette_spins'::regclass
      AND contype='f'
      AND confrelid='public.books'::regclass
      AND conkey=ARRAY[(
        SELECT attnum FROM pg_attribute
        WHERE attrelid='public.book_roulette_spins'::regclass
          AND attname='selected_book_id'
      )]::smallint[]
  ) THEN
    ALTER TABLE public.book_roulette_spins
      ADD CONSTRAINT book_roulette_spins_selected_book_id_fkey
      FOREIGN KEY (selected_book_id) REFERENCES public.books(id) ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.book_roulette_spins'::regclass
      AND contype='f'
      AND confrelid='public.members'::regclass
      AND conkey=ARRAY[(
        SELECT attnum FROM pg_attribute
        WHERE attrelid='public.book_roulette_spins'::regclass
          AND attname='spun_by_member_id'
      )]::smallint[]
  ) THEN
    ALTER TABLE public.book_roulette_spins
      ADD CONSTRAINT book_roulette_spins_spun_by_member_id_fkey
      FOREIGN KEY (spun_by_member_id) REFERENCES public.members(id) ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.book_roulette_spins'::regclass
      AND contype='f'
      AND confrelid='public.members'::regclass
      AND conkey=ARRAY[(
        SELECT attnum FROM pg_attribute
        WHERE attrelid='public.book_roulette_spins'::regclass
          AND attname='vetoed_by_member_id'
      )]::smallint[]
  ) THEN
    ALTER TABLE public.book_roulette_spins
      ADD CONSTRAINT book_roulette_spins_vetoed_by_member_id_fkey
      FOREIGN KEY (vetoed_by_member_id) REFERENCES public.members(id) ON DELETE RESTRICT;
  END IF;
END $$;

ALTER TABLE public.book_roulette_spins
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'selected',
  ADD COLUMN IF NOT EXISTS veto_reason text,
  ADD COLUMN IF NOT EXISTS vetoed_at timestamptz,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.book_roulette_spins'::regclass
      AND conname='book_roulette_spins_status_check'
  ) THEN
    ALTER TABLE public.book_roulette_spins
      ADD CONSTRAINT book_roulette_spins_status_check
      CHECK (status IN ('selected','vetoed','approved'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS book_roulette_spins_created_idx
  ON public.book_roulette_spins(created_at DESC);
CREATE INDEX IF NOT EXISTS book_roulette_spins_veto_cooldown_idx
  ON public.book_roulette_spins(vetoed_by_member_id,vetoed_at DESC)
  WHERE vetoed_by_member_id IS NOT NULL;

ALTER TABLE public.book_roulette_spins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.book_roulette_spins FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.book_roulette_spins TO authenticated;

DO $$
DECLARE
  v_policy record;
BEGIN
  FOR v_policy IN
    SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='book_roulette_spins'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.book_roulette_spins',v_policy.policyname);
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.current_club_member_id_text()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT m.id::text FROM public.members m
  WHERE m.user_id=auth.uid()
  LIMIT 1
$$;
REVOKE ALL ON FUNCTION public.current_club_member_id_text() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_club_member_id_text() TO authenticated;

CREATE POLICY book_roulette_spins_member_read ON public.book_roulette_spins
  FOR SELECT TO authenticated
  USING (public.current_club_member_id_text() IS NOT NULL);

CREATE OR REPLACE FUNCTION public.spin_book_roulette(p_candidate_book_ids jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_member_id public.members.id%TYPE;
  v_book_id public.books.id%TYPE;
  v_spin_id uuid;
BEGIN
  SELECT m.id INTO v_member_id
  FROM public.members m WHERE m.user_id=auth.uid() LIMIT 1;
  IF auth.uid() IS NULL OR v_member_id IS NULL THEN
    RAISE EXCEPTION 'A linked club member account is required.' USING ERRCODE='42501';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('book_roulette_spins',0));
  IF jsonb_typeof(p_candidate_book_ids) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Candidate book IDs must be sent as an array.';
  END IF;
  IF jsonb_array_length(p_candidate_book_ids)=0 THEN
    RAISE EXCEPTION 'Select at least one book for the roulette.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.book_roulette_spins WHERE status='selected'
  ) THEN
    RAISE EXCEPTION 'A roulette result is awaiting approval or veto.';
  END IF;

  EXECUTE $query$
    SELECT b.id
    FROM public.books b
    WHERE b.id::text IN (SELECT jsonb_array_elements_text($1))
      AND lower(btrim(COALESCE(b.status::text,''))) NOT IN
        ('قيد القراءة','تمت قراءته','مقروء','مكتمل','مكتملة','read','completed','complete','finished','in_progress')
    ORDER BY random()
    LIMIT 1
  $query$ INTO v_book_id USING p_candidate_book_ids;
  IF v_book_id IS NULL THEN
    RAISE EXCEPTION 'No eligible books remain in the selected roulette list.';
  END IF;

  INSERT INTO public.book_roulette_spins(selected_book_id,spun_by_member_id,status)
  VALUES (v_book_id,v_member_id,'selected')
  RETURNING id INTO v_spin_id;
  RETURN jsonb_build_object(
    'id',v_spin_id,
    'selected_book_id',v_book_id::text,
    'spun_by_member_id',v_member_id::text,
    'status','selected'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_book_roulette(p_spin_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_member_id public.members.id%TYPE;
  v_book_id public.books.id%TYPE;
  v_status text;
  v_updated_rows bigint;
BEGIN
  SELECT m.id INTO v_member_id
  FROM public.members m WHERE m.user_id=auth.uid() LIMIT 1;
  IF auth.uid() IS NULL OR v_member_id IS NULL THEN
    RAISE EXCEPTION 'A linked club member account is required.' USING ERRCODE='42501';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('book_roulette_spins',0));
  SELECT selected_book_id,status INTO v_book_id,v_status
  FROM public.book_roulette_spins WHERE id=p_spin_id FOR UPDATE;
  IF NOT FOUND OR v_status<>'selected' THEN
    RAISE EXCEPTION 'This roulette spin is no longer awaiting a decision.';
  END IF;

  EXECUTE 'UPDATE public.books SET status=$1 WHERE id=$2'
    USING 'قيد القراءة',v_book_id;
  GET DIAGNOSTICS v_updated_rows = ROW_COUNT;
  IF v_updated_rows=0 THEN RAISE EXCEPTION 'The selected book no longer exists.'; END IF;

  UPDATE public.book_roulette_spins SET status='approved'
  WHERE id=p_spin_id;
  RETURN jsonb_build_object('id',p_spin_id,'selected_book_id',v_book_id::text,'status','approved');
END;
$$;

CREATE OR REPLACE FUNCTION public.veto_book_roulette(p_spin_id uuid,p_veto_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_member_id public.members.id%TYPE;
  v_status text;
BEGIN
  SELECT m.id INTO v_member_id
  FROM public.members m WHERE m.user_id=auth.uid() LIMIT 1;
  IF auth.uid() IS NULL OR v_member_id IS NULL THEN
    RAISE EXCEPTION 'A linked club member account is required.' USING ERRCODE='42501';
  END IF;
  IF p_veto_reason IS NULL OR char_length(btrim(p_veto_reason)) NOT BETWEEN 3 AND 500 THEN
    RAISE EXCEPTION 'Write a veto reason between 3 and 500 characters.';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('book_roulette_spins',0));
  IF EXISTS (
    SELECT 1 FROM public.book_roulette_spins
    WHERE vetoed_by_member_id=v_member_id
      AND vetoed_at>=now()-interval '90 days'
  ) THEN
    RAISE EXCEPTION 'Your veto is on cooldown for 90 days.' USING ERRCODE='P0001';
  END IF;

  SELECT status INTO v_status FROM public.book_roulette_spins
  WHERE id=p_spin_id FOR UPDATE;
  IF NOT FOUND OR v_status<>'selected' THEN
    RAISE EXCEPTION 'This roulette spin is no longer awaiting a decision.';
  END IF;

  UPDATE public.book_roulette_spins
  SET status='vetoed',vetoed_by_member_id=v_member_id,
      veto_reason=btrim(p_veto_reason),vetoed_at=now()
  WHERE id=p_spin_id;
  RETURN jsonb_build_object('id',p_spin_id,'status','vetoed','vetoed_by_member_id',v_member_id::text);
END;
$$;

REVOKE ALL ON FUNCTION public.spin_book_roulette(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.approve_book_roulette(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.veto_book_roulette(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.spin_book_roulette(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_book_roulette(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.veto_book_roulette(uuid,text) TO authenticated;

COMMIT;
