do $$
begin
  begin
    alter publication supabase_realtime add table public.wallet_transactions;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;

  begin
    alter publication supabase_realtime add table public.drivers_profiles;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
end;
$$;

