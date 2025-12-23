create or replace function public.is_restaurant_owner_of_branch(p_branch_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.branches b
    where b.id = p_branch_id
      and b.restaurant_id = auth.uid()
  );
$$;

grant execute on function public.is_restaurant_owner_of_branch(bigint) to authenticated;

create or replace function public.can_driver_view_branch(p_branch_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
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
      where o.branch_id = p_branch_id
        and (o.status in ('pending', 'pending_repost') or o.driver_id = auth.uid())
    );
$$;

grant execute on function public.can_driver_view_branch(bigint) to authenticated;

drop policy if exists "Drivers can view branches for visible orders" on public.branches;
create policy "Drivers can view branches for visible orders" on public.branches for select
using (public.can_driver_view_branch(branches.id));

drop policy if exists "Restaurants can view orders for own branches" on public.orders;
create policy "Restaurants can view orders for own branches" on public.orders for select
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'restaurant'
      and (
        coalesce(p.is_approved, false) = true
        or coalesce(p.approval_status, 'pending') = 'approved'
      )
  )
  and public.is_restaurant_owner_of_branch(orders.branch_id)
);

drop policy if exists "Restaurants can create orders for own branches" on public.orders;
create policy "Restaurants can create orders for own branches" on public.orders for insert
with check (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'restaurant'
      and (
        coalesce(p.is_approved, false) = true
        or coalesce(p.approval_status, 'pending') = 'approved'
      )
  )
  and public.is_restaurant_owner_of_branch(orders.branch_id)
);
