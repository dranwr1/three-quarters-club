CREATE TABLE IF NOT EXISTS public.book_reading_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    book_id UUID NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
    member_id UUID NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
    pages_read INT NOT NULL DEFAULT 0 CHECK (pages_read >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (book_id, member_id)
);

ALTER TABLE public.book_reading_progress
    ADD COLUMN IF NOT EXISTS verified_by_ai BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS verification_note TEXT;

ALTER TABLE public.book_court_cases
    ADD COLUMN IF NOT EXISTS ai_final_verdict TEXT,
    ADD COLUMN IF NOT EXISTS ai_verdict_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS points_quiz_pass_achievement_key_uidx
    ON public.points (achievement_key)
    WHERE left(achievement_key, 10) = 'quiz_pass_';

ALTER TABLE public.book_reading_progress ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.book_reading_progress TO anon, authenticated;
GRANT INSERT, UPDATE ON public.book_reading_progress TO authenticated;

DROP POLICY IF EXISTS "Allow read access to everyone"
ON public.book_reading_progress;
CREATE POLICY "Allow read access to everyone"
ON public.book_reading_progress FOR SELECT
USING (true);

DROP POLICY IF EXISTS "Allow authenticated users to insert/update progress"
ON public.book_reading_progress;
DROP POLICY IF EXISTS "Members insert own reading progress"
ON public.book_reading_progress;
CREATE POLICY "Members insert own reading progress"
ON public.book_reading_progress FOR INSERT
TO authenticated
WITH CHECK (member_id = public.current_club_member_id());

DROP POLICY IF EXISTS "Members update own reading progress"
ON public.book_reading_progress;
CREATE POLICY "Members update own reading progress"
ON public.book_reading_progress FOR UPDATE
TO authenticated
USING (member_id = public.current_club_member_id())
WITH CHECK (member_id = public.current_club_member_id());
