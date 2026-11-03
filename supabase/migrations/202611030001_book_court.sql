BEGIN;

DO $$
DECLARE
  v_missing text[] := ARRAY[]::text[];
  v_data_type text;
BEGIN
  IF to_regclass('public.books') IS NULL THEN
    v_missing := array_append(v_missing, 'public.books');
  END IF;
  IF to_regclass('public.members') IS NULL THEN
    v_missing := array_append(v_missing, 'public.members');
  END IF;
  IF to_regclass('auth.users') IS NULL THEN
    v_missing := array_append(v_missing, 'auth.users');
  END IF;
  IF cardinality(v_missing) > 0 THEN
    RAISE EXCEPTION 'Book Court migration requires existing tables: %', array_to_string(v_missing, ', ');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='books' AND column_name='id'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='books' AND column_name='title'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='members' AND column_name='id'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='members' AND column_name='user_id'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='members' AND column_name='name'
  ) THEN
    RAISE EXCEPTION 'Book Court migration expected books(id,title) and members(id,user_id,name). Review the live schema before retrying.';
  END IF;

  SELECT data_type INTO v_data_type
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='books' AND column_name='id';
  IF v_data_type <> 'uuid' THEN
    RAISE EXCEPTION 'Expected public.books.id to be uuid, found %; migration stopped without changing existing tables.', v_data_type;
  END IF;

  SELECT data_type INTO v_data_type
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='members' AND column_name='id';
  IF v_data_type <> 'uuid' THEN
    RAISE EXCEPTION 'Expected public.members.id to be uuid, found %; migration stopped without changing existing tables.', v_data_type;
  END IF;

  SELECT data_type INTO v_data_type
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='members' AND column_name='user_id';
  IF v_data_type <> 'uuid' THEN
    RAISE EXCEPTION 'Expected public.members.user_id to be uuid, found %; migration stopped without changing existing tables.', v_data_type;
  END IF;

  IF EXISTS (
    SELECT user_id FROM public.members
    WHERE user_id IS NOT NULL GROUP BY user_id HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Duplicate non-null members.user_id values exist. Resolve them before applying the Book Court migration.';
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS members_user_id_book_court_uidx
  ON public.members(user_id) WHERE user_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.current_club_member_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT m.id
  FROM public.members AS m
  WHERE m.user_id = auth.uid()
  LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.is_club_member()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.members AS m WHERE m.user_id = auth.uid()
  )
$$;

REVOKE ALL ON FUNCTION public.current_club_member_id() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_club_member() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_club_member_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_club_member() TO authenticated;

CREATE TABLE IF NOT EXISTS public.book_court_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id uuid NOT NULL REFERENCES public.books(id) ON DELETE RESTRICT,
  title_snapshot text NOT NULL,
  created_by_member_id uuid NOT NULL REFERENCES public.members(id) ON DELETE RESTRICT,
  legacy_id text,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','closed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT book_court_cases_creator_legacy_key UNIQUE (created_by_member_id, legacy_id)
);

CREATE TABLE IF NOT EXISTS public.book_court_roles (
  case_id uuid NOT NULL REFERENCES public.book_court_cases(id) ON DELETE CASCADE,
  role_key text NOT NULL CHECK (role_key IN ('chaos','author','critic')),
  member_id uuid NOT NULL REFERENCES public.members(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (case_id, role_key),
  CONSTRAINT book_court_roles_one_role_per_member UNIQUE (case_id, member_id)
);

CREATE TABLE IF NOT EXISTS public.book_court_contributions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid NOT NULL REFERENCES public.book_court_cases(id) ON DELETE CASCADE,
  member_id uuid NOT NULL REFERENCES public.members(id) ON DELETE RESTRICT,
  stage text NOT NULL CHECK (stage IN ('مرافعة','نقاش','سؤال')),
  content text NOT NULL CHECK (char_length(btrim(content)) BETWEEN 30 AND 4000),
  legacy_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT book_court_contributions_id_case_member_key UNIQUE (id, case_id, member_id),
  CONSTRAINT book_court_contributions_case_legacy_key UNIQUE (case_id, legacy_id)
);

CREATE TABLE IF NOT EXISTS public.book_court_votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid NOT NULL REFERENCES public.book_court_cases(id) ON DELETE CASCADE,
  member_id uuid NOT NULL REFERENCES public.members(id) ON DELETE RESTRICT,
  choice text NOT NULL CHECK (choice IN ('recommend','discuss','not_recommend')),
  rationale text NOT NULL CHECK (char_length(btrim(rationale)) BETWEEN 1 AND 2000),
  legacy_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT book_court_votes_one_per_member UNIQUE (case_id, member_id),
  CONSTRAINT book_court_votes_id_case_member_key UNIQUE (id, case_id, member_id),
  CONSTRAINT book_court_votes_case_legacy_key UNIQUE (case_id, legacy_id)
);

CREATE TABLE IF NOT EXISTS public.book_court_achievements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid NOT NULL REFERENCES public.book_court_cases(id) ON DELETE CASCADE,
  member_id uuid NOT NULL REFERENCES public.members(id) ON DELETE RESTRICT,
  achievement_key text NOT NULL CHECK (achievement_key IN ('analysis','quote','evidence_error','court_participation','reasoned_vote')),
  contribution_id uuid,
  vote_id uuid,
  points smallint GENERATED ALWAYS AS (
    CASE achievement_key
      WHEN 'analysis' THEN 3
      WHEN 'quote' THEN 2
      WHEN 'evidence_error' THEN 5
      WHEN 'court_participation' THEN 2
      WHEN 'reasoned_vote' THEN 3
    END::smallint
  ) STORED,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT book_court_achievements_once_per_type UNIQUE (case_id, member_id, achievement_key),
  CONSTRAINT book_court_achievements_contribution_fk
    FOREIGN KEY (contribution_id, case_id, member_id)
    REFERENCES public.book_court_contributions(id, case_id, member_id) ON DELETE CASCADE,
  CONSTRAINT book_court_achievements_vote_fk
    FOREIGN KEY (vote_id, case_id, member_id)
    REFERENCES public.book_court_votes(id, case_id, member_id) ON DELETE CASCADE,
  CONSTRAINT book_court_achievements_source_check CHECK (
    (achievement_key='reasoned_vote' AND vote_id IS NOT NULL AND contribution_id IS NULL)
    OR
    (achievement_key<>'reasoned_vote' AND contribution_id IS NOT NULL AND vote_id IS NULL)
  )
);

CREATE INDEX IF NOT EXISTS book_court_cases_book_created_idx
  ON public.book_court_cases(book_id, created_at DESC);
CREATE INDEX IF NOT EXISTS book_court_roles_member_idx
  ON public.book_court_roles(member_id);
CREATE INDEX IF NOT EXISTS book_court_contributions_case_created_idx
  ON public.book_court_contributions(case_id, created_at DESC);
CREATE INDEX IF NOT EXISTS book_court_contributions_member_idx
  ON public.book_court_contributions(member_id, created_at DESC);
CREATE INDEX IF NOT EXISTS book_court_votes_case_idx
  ON public.book_court_votes(case_id);
CREATE INDEX IF NOT EXISTS book_court_achievements_member_idx
  ON public.book_court_achievements(member_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.enforce_book_court_achievement_source()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.achievement_key = 'reasoned_vote' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.book_court_votes AS v
      WHERE v.id=NEW.vote_id AND v.case_id=NEW.case_id
        AND v.member_id=NEW.member_id AND char_length(btrim(v.rationale)) >= 40
    ) THEN
      RAISE EXCEPTION 'A reasoned-vote achievement requires the member''s vote with at least 40 characters of rationale.';
    END IF;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM public.book_court_contributions AS c
      WHERE c.id=NEW.contribution_id AND c.case_id=NEW.case_id
        AND c.member_id=NEW.member_id AND char_length(btrim(c.content)) >= 30
    ) THEN
      RAISE EXCEPTION 'A court achievement requires the member''s substantive contribution.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS book_court_achievement_source_guard ON public.book_court_achievements;
CREATE TRIGGER book_court_achievement_source_guard
  BEFORE INSERT ON public.book_court_achievements
  FOR EACH ROW EXECUTE FUNCTION public.enforce_book_court_achievement_source();

ALTER TABLE public.book_court_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.book_court_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.book_court_contributions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.book_court_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.book_court_achievements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS book_court_cases_member_read ON public.book_court_cases;
CREATE POLICY book_court_cases_member_read ON public.book_court_cases
  FOR SELECT TO authenticated USING (public.is_club_member());
DROP POLICY IF EXISTS book_court_roles_member_read ON public.book_court_roles;
CREATE POLICY book_court_roles_member_read ON public.book_court_roles
  FOR SELECT TO authenticated USING (public.is_club_member());
DROP POLICY IF EXISTS book_court_contributions_member_read ON public.book_court_contributions;
CREATE POLICY book_court_contributions_member_read ON public.book_court_contributions
  FOR SELECT TO authenticated USING (public.is_club_member());
DROP POLICY IF EXISTS book_court_votes_member_read ON public.book_court_votes;
CREATE POLICY book_court_votes_member_read ON public.book_court_votes
  FOR SELECT TO authenticated USING (public.is_club_member());
DROP POLICY IF EXISTS book_court_achievements_member_read ON public.book_court_achievements;
CREATE POLICY book_court_achievements_member_read ON public.book_court_achievements
  FOR SELECT TO authenticated USING (public.is_club_member());

REVOKE ALL ON public.book_court_cases, public.book_court_roles,
  public.book_court_contributions, public.book_court_votes,
  public.book_court_achievements FROM anon, authenticated;
GRANT SELECT ON public.book_court_cases, public.book_court_roles,
  public.book_court_contributions, public.book_court_votes,
  public.book_court_achievements TO authenticated;

CREATE OR REPLACE FUNCTION public.create_book_court(
  p_book_id uuid,
  p_chaos_member_id uuid,
  p_author_member_id uuid,
  p_critic_member_id uuid,
  p_legacy_id text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_creator_id uuid := public.current_club_member_id();
  v_case_id uuid;
  v_book_title text;
BEGIN
  IF auth.uid() IS NULL OR v_creator_id IS NULL THEN
    RAISE EXCEPTION 'A linked club member account is required.' USING ERRCODE='42501';
  END IF;
  IF p_chaos_member_id IS NULL OR p_author_member_id IS NULL OR p_critic_member_id IS NULL
     OR cardinality(ARRAY[p_chaos_member_id,p_author_member_id,p_critic_member_id]) <> 3
     OR p_chaos_member_id=p_author_member_id OR p_chaos_member_id=p_critic_member_id
     OR p_author_member_id=p_critic_member_id THEN
    RAISE EXCEPTION 'Assign the three court roles to three different club members.';
  END IF;
  IF p_legacy_id IS NOT NULL AND char_length(p_legacy_id) > 200 THEN
    RAISE EXCEPTION 'Legacy case identifier is too long.';
  END IF;

  SELECT b.title INTO v_book_title FROM public.books AS b WHERE b.id=p_book_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The selected book does not exist.';
  END IF;

  IF p_legacy_id IS NOT NULL THEN
    SELECT c.id INTO v_case_id FROM public.book_court_cases AS c
    WHERE c.created_by_member_id=v_creator_id AND c.legacy_id=p_legacy_id;
    IF FOUND THEN RETURN v_case_id; END IF;
  END IF;

  INSERT INTO public.book_court_cases(book_id,title_snapshot,created_by_member_id,legacy_id)
  VALUES (p_book_id,v_book_title,v_creator_id,p_legacy_id)
  ON CONFLICT (created_by_member_id,legacy_id) DO NOTHING
  RETURNING id INTO v_case_id;

  IF v_case_id IS NULL THEN
    SELECT c.id INTO v_case_id FROM public.book_court_cases AS c
    WHERE c.created_by_member_id=v_creator_id AND c.legacy_id=p_legacy_id;
    RETURN v_case_id;
  END IF;

  INSERT INTO public.book_court_roles(case_id,role_key,member_id) VALUES
    (v_case_id,'chaos',p_chaos_member_id),
    (v_case_id,'author',p_author_member_id),
    (v_case_id,'critic',p_critic_member_id);
  RETURN v_case_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_book_court_contribution(
  p_case_id uuid,
  p_stage text,
  p_content text,
  p_achievement_key text DEFAULT NULL,
  p_legacy_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_member_id uuid := public.current_club_member_id();
  v_contribution_id uuid;
  v_points integer := 0;
BEGIN
  IF auth.uid() IS NULL OR v_member_id IS NULL THEN
    RAISE EXCEPTION 'A linked club member account is required.' USING ERRCODE='42501';
  END IF;
  IF p_stage NOT IN ('مرافعة','نقاش','سؤال') THEN
    RAISE EXCEPTION 'Invalid court contribution stage.';
  END IF;
  IF char_length(btrim(p_content)) NOT BETWEEN 30 AND 4000 THEN
    RAISE EXCEPTION 'A contribution must contain 30 to 4000 characters.';
  END IF;
  IF p_achievement_key IS NOT NULL AND p_achievement_key NOT IN ('analysis','quote','evidence_error') THEN
    RAISE EXCEPTION 'Invalid contribution achievement.';
  END IF;
  IF p_legacy_id IS NOT NULL AND char_length(p_legacy_id) > 240 THEN
    RAISE EXCEPTION 'Legacy contribution identifier is too long.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.book_court_cases WHERE id=p_case_id AND status='open') THEN
    RAISE EXCEPTION 'The court case is missing or closed.';
  END IF;

  IF p_legacy_id IS NOT NULL THEN
    SELECT id INTO v_contribution_id FROM public.book_court_contributions
    WHERE case_id=p_case_id AND legacy_id=p_legacy_id;
    IF FOUND THEN RETURN jsonb_build_object('id',v_contribution_id,'duplicate',true); END IF;
  END IF;

  INSERT INTO public.book_court_contributions(case_id,member_id,stage,content,legacy_id)
  VALUES (p_case_id,v_member_id,p_stage,btrim(p_content),p_legacy_id)
  ON CONFLICT (case_id,legacy_id) DO NOTHING
  RETURNING id INTO v_contribution_id;
  IF v_contribution_id IS NULL THEN
    SELECT id INTO v_contribution_id FROM public.book_court_contributions
    WHERE case_id=p_case_id AND legacy_id=p_legacy_id;
    RETURN jsonb_build_object('id',v_contribution_id,'duplicate',true);
  END IF;

  INSERT INTO public.book_court_achievements(case_id,member_id,achievement_key,contribution_id)
  VALUES (p_case_id,v_member_id,'court_participation',v_contribution_id)
  ON CONFLICT (case_id,member_id,achievement_key) DO NOTHING;
  IF FOUND THEN v_points := v_points + 2; END IF;

  IF p_achievement_key IS NOT NULL THEN
    INSERT INTO public.book_court_achievements(case_id,member_id,achievement_key,contribution_id)
    VALUES (p_case_id,v_member_id,p_achievement_key,v_contribution_id)
    ON CONFLICT (case_id,member_id,achievement_key) DO NOTHING;
    IF FOUND THEN
      v_points := v_points + CASE p_achievement_key WHEN 'analysis' THEN 3 WHEN 'quote' THEN 2 WHEN 'evidence_error' THEN 5 END;
    END IF;
  END IF;

  RETURN jsonb_build_object('id',v_contribution_id,'points_awarded',v_points,'duplicate',false);
END;
$$;

CREATE OR REPLACE FUNCTION public.cast_book_court_vote(
  p_case_id uuid,
  p_choice text,
  p_rationale text,
  p_legacy_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_member_id uuid := public.current_club_member_id();
  v_vote_id uuid;
  v_points integer := 0;
BEGIN
  IF auth.uid() IS NULL OR v_member_id IS NULL THEN
    RAISE EXCEPTION 'A linked club member account is required.' USING ERRCODE='42501';
  END IF;
  IF p_choice NOT IN ('recommend','discuss','not_recommend') THEN
    RAISE EXCEPTION 'Invalid final vote.';
  END IF;
  IF char_length(btrim(p_rationale)) NOT BETWEEN 1 AND 2000 THEN
    RAISE EXCEPTION 'A vote rationale must contain 1 to 2000 characters.';
  END IF;
  IF p_legacy_id IS NOT NULL AND char_length(p_legacy_id) > 240 THEN
    RAISE EXCEPTION 'Legacy vote identifier is too long.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.book_court_cases WHERE id=p_case_id AND status='open') THEN
    RAISE EXCEPTION 'The court case is missing or closed.';
  END IF;

  IF p_legacy_id IS NOT NULL THEN
    SELECT id INTO v_vote_id FROM public.book_court_votes
    WHERE case_id=p_case_id AND legacy_id=p_legacy_id;
    IF FOUND THEN RETURN jsonb_build_object('id',v_vote_id,'duplicate',true); END IF;
  END IF;

  INSERT INTO public.book_court_votes(case_id,member_id,choice,rationale,legacy_id)
  VALUES (p_case_id,v_member_id,p_choice,btrim(p_rationale),p_legacy_id)
  ON CONFLICT (case_id,member_id) DO NOTHING
  RETURNING id INTO v_vote_id;
  IF v_vote_id IS NULL THEN
    SELECT id INTO v_vote_id FROM public.book_court_votes
    WHERE case_id=p_case_id AND member_id=v_member_id;
    RETURN jsonb_build_object('id',v_vote_id,'duplicate',true);
  END IF;

  IF char_length(btrim(p_rationale)) >= 40 THEN
    INSERT INTO public.book_court_achievements(case_id,member_id,achievement_key,vote_id)
    VALUES (p_case_id,v_member_id,'reasoned_vote',v_vote_id)
    ON CONFLICT (case_id,member_id,achievement_key) DO NOTHING;
    IF FOUND THEN v_points := 3; END IF;
  END IF;

  RETURN jsonb_build_object('id',v_vote_id,'points_awarded',v_points,'duplicate',false);
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_book_court_achievement_source() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_book_court(uuid,uuid,uuid,uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.submit_book_court_contribution(uuid,text,text,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cast_book_court_vote(uuid,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_book_court(uuid,uuid,uuid,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_book_court_contribution(uuid,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cast_book_court_vote(uuid,text,text,text) TO authenticated;

DO $$
DECLARE
  v_table text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime') THEN
    FOREACH v_table IN ARRAY ARRAY[
      'book_court_cases','book_court_roles','book_court_contributions',
      'book_court_votes','book_court_achievements'
    ] LOOP
      IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename=v_table
      ) THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I',v_table);
      END IF;
    END LOOP;
  ELSE
    RAISE NOTICE 'supabase_realtime publication is unavailable; the client can still refresh manually.';
  END IF;
END $$;

COMMIT;
