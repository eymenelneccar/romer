do $$
declare
  c record;
begin
  for c in
    select conname
    from pg_constraint
    where conrelid = 'public.orders'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%status%'
  loop
    execute format('alter table public.orders drop constraint %I', c.conname);
  end loop;
end
$$;

alter table public.orders
  add constraint orders_status_check
  check (status in ('pending', 'pending_repost', 'accepted', 'picked_up', 'delivered', 'cancelled'));

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
where o.status in ('pending', 'pending_repost') or o.driver_id = auth.uid();

grant select on public.driver_orders_with_branch to authenticated;

create or replace function public.accept_order(p_order_id bigint)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver_id uuid := auth.uid();
  v_role text;
  v_status text;
  v_existing_driver uuid;
begin
  if v_driver_id is null then
    raise exception 'Not authenticated';
  end if;

  select role into v_role from public.profiles where id = v_driver_id;
  if v_role is distinct from 'driver' then
    raise exception 'Only drivers can accept orders';
  end if;

  select status, driver_id
  into v_status, v_existing_driver
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    return 'already_taken';
  end if;

  if v_status not in ('pending', 'pending_repost') or v_existing_driver is not null then
    return 'already_taken';
  end if;

  update public.orders
  set status = 'accepted',
      driver_id = v_driver_id
  where id = p_order_id;

  if found then
    return 'success';
  end if;

  return 'already_taken';
end;
$$;

grant execute on function public.accept_order(bigint) to authenticated;

create or replace function public.restaurant_resend_order(p_order_id bigint)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restaurant_id uuid := auth.uid();
  v_role text;
  v_is_approved boolean;
  v_status text;
  v_driver_id uuid;
  v_details jsonb;
  v_prev_count int;
  v_now timestamptz := timezone('utc'::text, now());
  v_now_iso text := to_char(v_now, 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"');
begin
  if v_restaurant_id is null then
    raise exception 'Not authenticated';
  end if;

  select p.role, coalesce(p.is_approved, false)
  into v_role, v_is_approved
  from public.profiles p
  where p.id = v_restaurant_id;

  if v_role is distinct from 'restaurant' then
    raise exception 'Only restaurants can resend orders';
  end if;
  if v_is_approved is distinct from true then
    raise exception 'Restaurant not approved';
  end if;

  select o.status, o.driver_id, coalesce(o.customer_details, '{}'::jsonb)
  into v_status, v_driver_id, v_details
  from public.orders o
  join public.branches b on b.id = o.branch_id
  where o.id = p_order_id
    and b.restaurant_id = v_restaurant_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_status not in ('pending', 'pending_repost') then
    raise exception 'Order is not pending';
  end if;
  if v_driver_id is not null then
    raise exception 'Order already accepted';
  end if;

  v_prev_count := coalesce(nullif((v_details->>'resend_count')::text, '')::int, 0);
  v_details := jsonb_set(v_details, '{resend_count}', to_jsonb(v_prev_count + 1), true);
  v_details := jsonb_set(v_details, '{resend_at}', to_jsonb(v_now_iso), true);

  update public.orders
  set customer_details = v_details,
      status = 'pending_repost'
  where id = p_order_id;

  return true;
end;
$$;

grant execute on function public.restaurant_resend_order(bigint) to authenticated;

drop policy if exists "Drivers can view available or assigned orders" on public.orders;
create policy "Drivers can view available or assigned orders" on public.orders for select
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'driver'
      and (
        coalesce(p.is_approved, false) = true
        or coalesce(p.approval_status, 'pending') = 'approved'
      )
  )
  and
  (status in ('pending', 'pending_repost') or driver_id = auth.uid())
);

drop policy if exists "Drivers can view branches for visible orders" on public.branches;
create policy "Drivers can view branches for visible orders" on public.branches for select
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'driver'
      and (
        coalesce(p.is_approved, false) = true
        or coalesce(p.approval_status, 'pending') = 'approved'
      )
  )
  and
  exists (
    select 1
    from public.orders o
    where o.branch_id = branches.id
      and (o.status in ('pending', 'pending_repost') or o.driver_id = auth.uid())
  )
);
