alter table public.item_photos
  add constraint item_photos_item_id_position_key unique (item_id, position);
