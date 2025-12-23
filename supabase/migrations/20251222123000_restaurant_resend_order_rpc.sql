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
  v_now_iso text := to_char(v_now, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
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

  if v_status is distinct from 'pending' then
    raise exception 'Order is not pending';
  end if;
  if v_driver_id is not null then
    raise exception 'Order already accepted';
  end if;

  v_prev_count := coalesce(nullif((v_details->>'resend_count')::text, '')::int, 0);
  v_details := jsonb_set(v_details, '{resend_count}', to_jsonb(v_prev_count + 1), true);
  v_details := jsonb_set(v_details, '{resend_at}', to_jsonb(v_now_iso), true);

  update public.orders
  set customer_details = v_details
  where id = p_order_id;

  return true;
end;
$$;

grant execute on function public.restaurant_resend_order(bigint) to authenticated;