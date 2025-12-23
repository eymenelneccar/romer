create or replace function public.admin_settle_driver_wallet(p_driver_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id uuid := auth.uid();
  v_role text;
  v_prev numeric;
  v_tx_id bigint;
  v_now timestamptz := timezone('utc'::text, now());
  v_now_iso text := to_char(v_now, 'YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"');
begin
  if v_admin_id is null then
    raise exception 'Not authenticated';
  end if;

  select role
  into v_role
  from public.profiles
  where id = v_admin_id;

  if v_role is distinct from 'admin' then
    raise exception 'Only admins can settle wallets';
  end if;

  insert into public.drivers_profiles (id, wallet_balance)
  values (p_driver_id, 0)
  on conflict (id) do nothing;

  select wallet_balance
  into v_prev
  from public.drivers_profiles
  where id = p_driver_id
  for update;

  v_prev := coalesce(v_prev, 0);

  update public.drivers_profiles
  set wallet_balance = 0
  where id = p_driver_id;

  insert into public.wallet_transactions (driver_id, amount, type, naemi_percentage, created_at)
  values (p_driver_id, v_prev, 'withdrawal', 0, v_now)
  returning id into v_tx_id;

  return jsonb_build_object(
    'driver_id', p_driver_id,
    'previous_balance', v_prev,
    'new_balance', 0,
    'transaction_id', v_tx_id,
    'created_at', v_now_iso
  );
end;
$$;

grant execute on function public.admin_settle_driver_wallet(uuid) to authenticated;
