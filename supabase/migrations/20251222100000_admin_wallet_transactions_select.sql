drop policy if exists "Admins can view all wallet transactions" on public.wallet_transactions;
create policy "Admins can view all wallet transactions" on public.wallet_transactions for select
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  )
);

