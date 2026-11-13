DO $$
DECLARE
  v_data_type text;
  v_has_notes boolean;
  v_has_likes boolean;
BEGIN
  SELECT data_type INTO v_data_type
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='books' AND column_name='id';
  IF v_data_type IS DISTINCT FROM 'uuid' THEN
    RAISE EXCEPTION 'Margin notes require public.books.id to be uuid; found %.', COALESCE(v_data_type, 'missing');
  END IF;

  SELECT data_type INTO v_data_type
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='members' AND column_name='id';
  IF v_data_type IS DISTINCT FROM 'uuid' THEN
    RAISE EXCEPTION 'Margin notes require public.members.id to be uuid; found %.', COALESCE(v_data_type, 'missing');
  END IF;

  v_has_notes := to_regclass('public.book_margin_notes') IS NOT NULL;
  v_has_likes := to_regclass('public.book_margin_note_likes') IS NOT NULL;

  IF v_has_notes AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='book_margin_notes'
      AND column_name IN ('book_id','member_id') AND data_type <> 'uuid'
  ) THEN
    IF EXISTS (SELECT 1 FROM public.book_margin_notes LIMIT 1) THEN
      RAISE EXCEPTION 'public.book_margin_notes contains data with non-UUID book_id/member_id. Migrate those values to actual UUIDs before applying this migration.';
    END IF;
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='book_margin_notes'
        AND column_name='book_id' AND data_type <> 'uuid'
    ) THEN
      ALTER TABLE public.book_margin_notes ALTER COLUMN book_id TYPE uuid USING NULL::uuid;
    END IF;
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='book_margin_notes'
        AND column_name='member_id' AND data_type <> 'uuid'
    ) THEN
      ALTER TABLE public.book_margin_notes ALTER COLUMN member_id TYPE uuid USING NULL::uuid;
    END IF;
  END IF;

  IF v_has_likes AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='book_margin_note_likes'
      AND column_name='member_id' AND data_type <> 'uuid'
  ) THEN
    IF EXISTS (SELECT 1 FROM public.book_margin_note_likes LIMIT 1) THEN
      RAISE EXCEPTION 'public.book_margin_note_likes contains data with non-UUID member_id. Migrate those values to actual UUIDs before applying this migration.';
    END IF;
    ALTER TABLE public.book_margin_note_likes ALTER COLUMN member_id TYPE uuid USING NULL::uuid;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.book_margin_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id uuid NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
  member_id uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  note_type text NOT NULL CHECK (note_type IN ('quote','thought','critique')),
  page_number integer CHECK (page_number IS NULL OR page_number > 0),
  content text NOT NULL CHECK (char_length(btrim(content)) BETWEEN 1 AND 4000),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.book_margin_note_likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  note_id uuid NOT NULL REFERENCES public.book_margin_notes(id) ON DELETE CASCADE,
  member_id uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT book_margin_note_likes_note_member_key UNIQUE (note_id, member_id)
);

ALTER TABLE public.book_margin_notes
  ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE public.book_margin_note_likes
  ALTER COLUMN id SET DEFAULT gen_random_uuid();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.book_margin_notes'::regclass
      AND conname='book_margin_notes_book_id_fkey'
  ) THEN
    ALTER TABLE public.book_margin_notes
      ADD CONSTRAINT book_margin_notes_book_id_fkey
      FOREIGN KEY (book_id) REFERENCES public.books(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.book_margin_notes'::regclass
      AND conname='book_margin_notes_member_id_fkey'
  ) THEN
    ALTER TABLE public.book_margin_notes
      ADD CONSTRAINT book_margin_notes_member_id_fkey
      FOREIGN KEY (member_id) REFERENCES public.members(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.book_margin_note_likes'::regclass
      AND conname='book_margin_note_likes_note_id_fkey'
  ) THEN
    ALTER TABLE public.book_margin_note_likes
      ADD CONSTRAINT book_margin_note_likes_note_id_fkey
      FOREIGN KEY (note_id) REFERENCES public.book_margin_notes(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.book_margin_note_likes'::regclass
      AND conname='book_margin_note_likes_member_id_fkey'
  ) THEN
    ALTER TABLE public.book_margin_note_likes
      ADD CONSTRAINT book_margin_note_likes_member_id_fkey
      FOREIGN KEY (member_id) REFERENCES public.members(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.book_margin_note_likes'::regclass
      AND conname='book_margin_note_likes_note_member_key'
  ) THEN
    ALTER TABLE public.book_margin_note_likes
      ADD CONSTRAINT book_margin_note_likes_note_member_key UNIQUE (note_id, member_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS book_margin_notes_book_created_idx
  ON public.book_margin_notes(book_id, created_at DESC);
CREATE INDEX IF NOT EXISTS book_margin_notes_member_created_idx
  ON public.book_margin_notes(member_id, created_at DESC);
CREATE INDEX IF NOT EXISTS book_margin_note_likes_note_idx
  ON public.book_margin_note_likes(note_id);

ALTER TABLE public.book_margin_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.book_margin_note_likes ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.book_margin_notes, public.book_margin_note_likes
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.book_margin_notes, public.book_margin_note_likes TO authenticated;
GRANT INSERT, DELETE ON public.book_margin_notes, public.book_margin_note_likes TO authenticated;

DO $$
DECLARE
  v_policy record;
BEGIN
  FOR v_policy IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname='public'
      AND tablename IN ('book_margin_notes','book_margin_note_likes')
  LOOP
    EXECUTE format('DROP POLICY %I ON %I.%I',
      v_policy.policyname,v_policy.schemaname,v_policy.tablename);
  END LOOP;
END $$;

CREATE POLICY book_margin_notes_member_read ON public.book_margin_notes
  FOR SELECT TO authenticated USING (public.is_club_member());
CREATE POLICY book_margin_notes_owner_insert ON public.book_margin_notes
  FOR INSERT TO authenticated
  WITH CHECK (member_id = public.current_club_member_id());
CREATE POLICY book_margin_notes_owner_delete ON public.book_margin_notes
  FOR DELETE TO authenticated
  USING (member_id = public.current_club_member_id());

CREATE POLICY book_margin_note_likes_member_read ON public.book_margin_note_likes
  FOR SELECT TO authenticated USING (public.is_club_member());
CREATE POLICY book_margin_note_likes_owner_insert ON public.book_margin_note_likes
  FOR INSERT TO authenticated
  WITH CHECK (member_id = public.current_club_member_id());
CREATE POLICY book_margin_note_likes_owner_delete ON public.book_margin_note_likes
  FOR DELETE TO authenticated
  USING (member_id = public.current_club_member_id());

CREATE UNIQUE INDEX IF NOT EXISTS points_first_margin_note_key_uidx
  ON public.points(achievement_key)
  WHERE left(achievement_key, 11) = 'first_note_';

CREATE OR REPLACE FUNCTION public.award_first_margin_note_points(p_book_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_member_id uuid := public.current_club_member_id();
  v_achievement_key text;
BEGIN
  IF auth.uid() IS NULL OR v_member_id IS NULL THEN
    RAISE EXCEPTION 'A linked club member account is required.' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.book_margin_notes
    WHERE book_id=p_book_id AND member_id=v_member_id AND note_type='quote'
  ) THEN
    RAISE EXCEPTION 'Add a quote before requesting its reward.';
  END IF;

  v_achievement_key := 'first_note_' || p_book_id::text || '_' || v_member_id::text;
  INSERT INTO public.points(member_id,achievement,points,achievement_key,reference_id)
  VALUES (v_member_id,'تدوين هامش في الكتاب',5,v_achievement_key,p_book_id)
  ON CONFLICT (achievement_key)
    WHERE left(achievement_key, 11) = 'first_note_'
    DO NOTHING;
  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.award_first_margin_note_points(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.award_first_margin_note_points(uuid) TO authenticated;
