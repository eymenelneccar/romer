alter table public.profiles
  add column if not exists restaurant_address text;

alter table public.branches
  add column if not exists address text;

create or replace function public.handle_new_user()
returns trigger as $$
declare
  v_requested_role text;
  v_avatar_url text;
  v_restaurant_address text;
begin
  v_requested_role := nullif(btrim(new.raw_user_meta_data->>'requested_role'), '');
  if v_requested_role is null then
    v_requested_role := 'driver';
  end if;
  if v_requested_role not in ('driver', 'restaurant') then
    v_requested_role := 'driver';
  end if;

  v_avatar_url := nullif(btrim(new.raw_user_meta_data->>'avatar_url'), '');
  v_restaurant_address := nullif(btrim(new.raw_user_meta_data->>'restaurant_address'), '');

  insert into public.profiles (id, email, role, name, requested_role, approval_status, is_approved, avatar_url, approval_requested_at, restaurant_address)
  values (
    new.id,
    new.email,
    'driver',
    new.raw_user_meta_data->>'name',
    v_requested_role,
    'pending',
    false,
    v_avatar_url,
    timezone('utc'::text, now()),
    v_restaurant_address
  )
  on conflict (id) do update set
    name = excluded.name,
    email = excluded.email,
    requested_role = excluded.requested_role,
    avatar_url = coalesce(excluded.avatar_url, public.profiles.avatar_url),
    restaurant_address = coalesce(excluded.restaurant_address, public.profiles.restaurant_address);

  update public.profiles
  set phone = nullif(new.raw_user_meta_data->>'phone', '')
  where id = new.id;

  return new;
end;
$$ language plpgsql security definer;

create or replace function public.admin_approve_membership(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requested_role text;
  v_restaurant_name text;
  v_restaurant_address text;
begin
  if not exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  ) then
    raise exception 'Only admins can approve memberships';
  end if;

  select requested_role into v_requested_role
  from public.profiles
  where id = p_user_id;

  if v_requested_role is null or v_requested_role not in ('driver', 'restaurant') then
    v_requested_role := 'driver';
  end if;

  update public.profiles
  set
    role = v_requested_role,
    approval_status = 'approved',
    is_approved = true
  where id = p_user_id;

  if v_requested_role = 'restaurant' then
    select nullif(btrim(p.name), ''), nullif(btrim(p.restaurant_address), '')
    into v_restaurant_name, v_restaurant_address
    from public.profiles p
    where p.id = p_user_id;

    if v_restaurant_name is null then
      v_restaurant_name := 'مطعم';
    end if;

    insert into public.branches (restaurant_name, restaurant_id, address, created_at)
    values (v_restaurant_name, p_user_id, v_restaurant_address, timezone('utc'::text, now()))
    on conflict (id) do nothing;

    update public.branches b
    set
      restaurant_name = coalesce(nullif(btrim(v_restaurant_name), ''), b.restaurant_name),
      address = coalesce(nullif(btrim(v_restaurant_address), ''), b.address)
    where b.restaurant_id = p_user_id;
  end if;
end;
$$;

create or replace view public.driver_orders_with_branch
with (security_barrier = true)
as
select
  o.id as order_id,
  o.status,
  o.driver_id,
  o.branch_id,
  ('فرع #' || b.id::text) as branch_name,
  b.lat,
  b.lng,
  b.restaurant_name,
  b.address as branch_address
from public.orders o
join public.branches b on b.id = o.branch_id
where o.status = 'pending' or o.driver_id = auth.uid();

update public.branches b
set address = p.restaurant_address
from public.profiles p
where b.restaurant_id = p.id
  and b.address is null
  and p.restaurant_address is not null;

