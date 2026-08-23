-- Confirmed Page-only production defect: published Page reviews/rating RPCs were not
-- checking Page lifecycle state, so a known review could remain directly readable
-- after the Page was deactivated/drafted/deleted.

DROP POLICY IF EXISTS page_reviews_select ON public.page_reviews;
CREATE POLICY page_reviews_select ON public.page_reviews
FOR SELECT USING (
  (
    status = 'published'
    AND EXISTS (
      SELECT 1 FROM public.pages p
      WHERE p.id = page_reviews.page_id
        AND p.status = 'published'
        AND p.deleted_at IS NULL
    )
  )
  OR user_id = auth.uid()
  OR public.current_user_page_role(page_id) = 'owner'
  OR public.current_user_has_page_permission(page_id, 'manage_reviews')
);

CREATE OR REPLACE FUNCTION public.get_page_reviews(
  p_page_id uuid,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0,
  p_sort text DEFAULT 'recent'
)
RETURNS TABLE(
  id uuid, page_id uuid, user_id uuid, username text, profile_photo_url text,
  rating smallint, title text, body text, status text, owner_response text,
  owner_response_at timestamptz, helpful_count integer, edited boolean,
  created_at timestamptz, updated_at timestamptz, voted_helpful boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = 'public'
AS $$
  SELECT
    r.id, r.page_id, r.user_id, u.username, u.profile_photo_url,
    r.rating, r.title, r.body, r.status, r.owner_response, r.owner_response_at,
    r.helpful_count, r.edited, r.created_at, r.updated_at,
    EXISTS (
      SELECT 1 FROM public.page_review_helpful_votes v
      WHERE v.review_id = r.id AND v.user_id = auth.uid()
    ) AS voted_helpful
  FROM public.page_reviews r
  JOIN public.users u ON u.id = r.user_id
  WHERE r.page_id = p_page_id
    AND (
      (
        r.status = 'published'
        AND EXISTS (
          SELECT 1 FROM public.pages p
          WHERE p.id = r.page_id
            AND p.status = 'published'
            AND p.deleted_at IS NULL
        )
      )
      OR r.user_id = auth.uid()
      OR public.current_user_page_role(p_page_id) = 'owner'
      OR public.current_user_has_page_permission(p_page_id, 'manage_reviews')
    )
  ORDER BY
    CASE WHEN p_sort = 'helpful' THEN r.helpful_count END DESC NULLS LAST,
    CASE WHEN p_sort = 'highest' THEN r.rating END DESC NULLS LAST,
    CASE WHEN p_sort = 'lowest' THEN r.rating END ASC NULLS LAST,
    r.created_at DESC
  LIMIT greatest(1, least(p_limit, 50))
  OFFSET greatest(0, p_offset);
$$;

CREATE OR REPLACE FUNCTION public.get_page_rating_breakdown(p_page_id uuid)
RETURNS TABLE(rating smallint, count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = 'public'
AS $$
  SELECT s.rating, coalesce(count(r.id), 0)
  FROM generate_series(1, 5) AS s(rating)
  LEFT JOIN public.page_reviews r
    ON r.page_id = p_page_id
   AND r.status = 'published'
   AND r.rating = s.rating
   AND EXISTS (
     SELECT 1 FROM public.pages p
     WHERE p.id = r.page_id
       AND p.status = 'published'
       AND p.deleted_at IS NULL
   )
  GROUP BY s.rating
  ORDER BY s.rating DESC;
$$;
