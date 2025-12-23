create or replace function public.admin_create_zone_and_set_price(
  p_restaurant_id uuid,
  p_zone_name text,
  p_delivery_fee numeric
)
returns table (out_zone_id bigint, out_zone_name text, out_delivery_fee numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_zone_id bigint;
  v_zone_name text;
begin
  if p_zone_name is null or btrim(p_zone_name) = '' then
    raise exception 'Zone name is required';
  end if;

  if p_delivery_fee is null or p_delivery_fee < 0 then
    raise exception 'Invalid delivery fee';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  ) then
    raise exception 'Only admins can manage zones';
  end if;

  select z.id, z.name
  into v_zone_id, v_zone_name
  from public.zones z
  where lower(btrim(z.name)) = lower(btrim(p_zone_name))
  limit 1;

  if v_zone_id is null then
    insert into public.zones (name, created_at)
    values (btrim(p_zone_name), timezone('utc'::text, now()))
    returning id, name into v_zone_id, v_zone_name;
  end if;

  insert into public.restaurant_zone_pricing (restaurant_id, zone_id, delivery_fee)
  values (p_restaurant_id, v_zone_id, p_delivery_fee)
  on conflict (restaurant_id, zone_id)
  do update set delivery_fee = excluded.delivery_fee;

  return query
  select v_zone_id, v_zone_name, p_delivery_fee;
end;
$$;

grant execute on function public.admin_create_zone_and_set_price(uuid, text, numeric) to authenticated;

