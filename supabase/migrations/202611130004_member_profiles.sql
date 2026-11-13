BEGIN;

DO $$
DECLARE
  v_member_id_type text;
BEGIN
  SELECT data_type INTO v_member_id_type
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='members' AND column_name='id';

  IF v_member_id_type IS DISTINCT FROM 'uuid' THEN
    RAISE EXCEPTION
      'Member profiles require public.members.id to be uuid; found %.',
      COALESCE(v_member_id_type,'missing');
  END IF;

  IF to_regprocedure('public.current_club_member_id()') IS NULL
     OR to_regprocedure('public.is_club_member()') IS NULL THEN
    RAISE EXCEPTION
      'Member profiles require public.current_club_member_id() and public.is_club_member(). Apply the Book Court migration first.';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.member_profiles (
  member_id uuid PRIMARY KEY
    REFERENCES public.members(id) ON DELETE CASCADE,
  bio text NOT NULL DEFAULT ''
    CHECK (char_length(bio) <= 500),
  favorite_genre text NOT NULL DEFAULT ''
    CHECK (char_length(favorite_genre) <= 100),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.member_profiles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.member_profiles FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.member_profiles TO authenticated;

DROP POLICY IF EXISTS member_profiles_club_read ON public.member_profiles;
CREATE POLICY member_profiles_club_read ON public.member_profiles
  FOR SELECT TO authenticated
  USING (public.is_club_member());

DROP POLICY IF EXISTS member_profiles_owner_insert ON public.member_profiles;
CREATE POLICY member_profiles_owner_insert ON public.member_profiles
  FOR INSERT TO authenticated
  WITH CHECK (member_id = public.current_club_member_id());

DROP POLICY IF EXISTS member_profiles_owner_update ON public.member_profiles;
CREATE POLICY member_profiles_owner_update ON public.member_profiles
  FOR UPDATE TO authenticated
  USING (member_id = public.current_club_member_id())
  WITH CHECK (member_id = public.current_club_member_id());

COMMIT;
