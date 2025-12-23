-- Backfill approval flag for already-approved users (older data may only have approval_status set)
update public.profiles
set is_approved = true
where coalesce(is_approved, false) = false
  and coalesce(approval_status, 'pending') = 'approved';

-- Ensure approved drivers can read pending/assigned orders
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
  (status = 'pending' or driver_id = auth.uid())
);

