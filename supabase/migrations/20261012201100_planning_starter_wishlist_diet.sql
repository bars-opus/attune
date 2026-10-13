-- Wishlist and Diet become starter categories (every couple has them),
-- placed after Groceries; the gallery stops offering them. Existing
-- couples get them on their next Planning open (planning_v2_ensure_starters
-- adds missing starters at the end of their list).

ALTER TABLE public.planning_categories DROP CONSTRAINT planning_categories_seed_key_check;
ALTER TABLE public.planning_categories ADD CONSTRAINT planning_categories_seed_key_check
  CHECK (seed_key IN ('notes','goals','trips','date_nights','home_bills','groceries','wishlist','diet','everyday'));

-- Everyday stays last.
UPDATE public.planning_starter_templates SET rank = 8 WHERE seed_key = 'everyday';

INSERT INTO public.planning_starter_templates (seed_key, version, name, icon, color, rank, template_title, blocks)
SELECT 'wishlist', 1, 'Wishlist', 'gift', 'orange', 6, 'Our wishlist', blocks
FROM public.planning_gallery_templates WHERE key = 'wishlist';
INSERT INTO public.planning_starter_templates (seed_key, version, name, icon, color, rank, template_title, blocks)
SELECT 'diet', 1, 'Diet', 'utensils', 'teal', 7, 'This week''s meals', blocks
FROM public.planning_gallery_templates WHERE key = 'diet';

DELETE FROM public.planning_gallery_templates WHERE key IN ('wishlist', 'diet');
