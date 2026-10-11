-- Follow-up to 20260812000000, which shipped two more-permissive-than-
-- necessary grants:
--
-- 1. item_photos delete was granted on the mistaken premise that FK cascade
--    deletes need RLS permission on the child table. Per Postgres docs,
--    referential integrity actions (including ON DELETE CASCADE) bypass row
--    security — items.delete already cleans up item_photos without it. The
--    grant instead let a client DELETE just the photo row while keeping the
--    item, leaving a permanently blank grid tile with no repair path.
-- 2. items update was granted table-wide instead of scoped to the columns
--    EditItemView actually edits.

drop policy "Item owners can delete photos of their own items" on public.item_photos;
revoke delete on public.item_photos from authenticated;

revoke update on public.items from authenticated;
grant update (category, size, color, occasion_tags, caption) on public.items to authenticated;
