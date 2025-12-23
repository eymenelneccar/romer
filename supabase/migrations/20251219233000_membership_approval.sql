alter table public.profiles
  add column if not exists requested_role text check (requested_role in ('driver', 'restaurant')),
  add column if not exists approval_status text check (approval_status in ('pending', 'approved', 'rejected')) default 'pending',
  add column if not exists is_approved boolean default false,
  add column if not exists avatar_url text,
  add column if not exists approval_requested_at timestamp with time zone default timezone('utc'::text, now());

drop policy if exists "Users can insert their own profile" on public.profiles;
create policy "Users can insert their own profile" on public.profiles for insert
with check (
  auth.uid() = id
  and role = 'driver'
  and coalesce(requested_role, 'driver') in ('driver', 'restaurant')
  and coalesce(approval_status, 'pending') = 'pending'
  and coalesce(is_approved, false) = false
);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile" on public.profiles for update
using (auth.uid() = id)
with check (
  auth.uid() = id
  and role = (
    select p.role
    from public.profiles p
    where p.id = auth.uid()
  )
  and requested_role = (
    select p.requested_role
    from public.profiles p
    where p.id = auth.uid()
  )
  and approval_status = (
    select p.approval_status
    from public.profiles p
    where p.id = auth.uid()
  )
  and is_approved = (
    select p.is_approved
    from public.profiles p
    where p.id = auth.uid()
  )
);

create or replace function public.handle_new_user()
returns trigger as $$
declare
  v_requested_role text;
  v_avatar_url text;
begin
  v_requested_role := nullif(btrim(new.raw_user_meta_data->>'requested_role'), '');
  if v_requested_role is null then
    v_requested_role := 'driver';
  end if;
  if v_requested_role not in ('driver', 'restaurant') then
    v_requested_role := 'driver';
  end if;

  v_avatar_url := nullif(btrim(new.raw_user_meta_data->>'avatar_url'), '');

  insert into public.profiles (id, email, role, name, requested_role, approval_status, is_approved, avatar_url, approval_requested_at)
  values (
    new.id,
    new.email,
    'driver',
    new.raw_user_meta_data->>'name',
    v_requested_role,
    'pending',
    false,
    v_avatar_url,
    timezone('utc'::text, now())
  )
  on conflict (id) do update set
    name = excluded.name,
    email = excluded.email,
    requested_role = excluded.requested_role,
    avatar_url = coalesce(excluded.avatar_url, public.profiles.avatar_url);

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
    select nullif(btrim(p.name), '') into v_restaurant_name
    from public.profiles p
    where p.id = p_user_id;
    if v_restaurant_name is null then
      v_restaurant_name := 'مطعم';
    end if;

    insert into public.branches (restaurant_name, restaurant_id, created_at)
    select v_restaurant_name, p_user_id, timezone('utc'::text, now())
    where not exists (
      select 1
      from public.branches b
      where b.restaurant_id = p_user_id
    );
  end if;
end;
$$;

create or replace function public.admin_reject_membership(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  ) then
    raise exception 'Only admins can reject memberships';
  end if;

  update public.profiles
  set
    approval_status = 'rejected',
    is_approved = false
  where id = p_user_id;
end;
$$;

grant execute on function public.admin_approve_membership(uuid) to authenticated;
grant execute on function public.admin_reject_membership(uuid) to authenticated;

insert into public.branches (restaurant_name, restaurant_id, created_at)
select
  coalesce(nullif(btrim(p.name), ''), 'مطعم'),
  p.id,
  timezone('utc'::text, now())
from public.profiles p
where p.role = 'restaurant'
  and coalesce(p.is_approved, false) = true
  and not exists (
    select 1
    from public.branches b
    where b.restaurant_id = p.id
  );

drop policy if exists "Drivers can view own driver profile" on public.drivers_profiles;
drop policy if exists "Drivers can insert own driver profile" on public.drivers_profiles;
drop policy if exists "Drivers can update own driver profile" on public.drivers_profiles;

create policy "Drivers can view own driver profile" on public.drivers_profiles for select
using (
  id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and coalesce(p.role, 'driver') = 'driver'
      and coalesce(p.is_approved, false) = true
  )
);

create policy "Drivers can insert own driver profile" on public.drivers_profiles for insert
with check (
  id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and coalesce(p.role, 'driver') = 'driver'
      and coalesce(p.is_approved, false) = true
  )
);

create policy "Drivers can update own driver profile" on public.drivers_profiles for update
using (
  id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and coalesce(p.role, 'driver') = 'driver'
      and coalesce(p.is_approved, false) = true
  )
)
with check (
  id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and coalesce(p.role, 'driver') = 'driver'
      and coalesce(p.is_approved, false) = true
  )
);

drop policy if exists "Drivers can view own availability slots" on public.driver_availability_slots;
drop policy if exists "Drivers can insert own availability slots" on public.driver_availability_slots;
drop policy if exists "Drivers can update own availability slots" on public.driver_availability_slots;
drop policy if exists "Drivers can delete own availability slots" on public.driver_availability_slots;

create policy "Drivers can view own availability slots" on public.driver_availability_slots for select
using (
  driver_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and coalesce(p.role, 'driver') = 'driver'
      and coalesce(p.is_approved, false) = true
  )
);

create policy "Drivers can insert own availability slots" on public.driver_availability_slots for insert
with check (
  driver_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and coalesce(p.role, 'driver') = 'driver'
      and coalesce(p.is_approved, false) = true
  )
);

create policy "Drivers can update own availability slots" on public.driver_availability_slots for update
using (
  driver_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and coalesce(p.role, 'driver') = 'driver'
      and coalesce(p.is_approved, false) = true
  )
)
with check (
  driver_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and coalesce(p.role, 'driver') = 'driver'
      and coalesce(p.is_approved, false) = true
  )
);

create policy "Drivers can delete own availability slots" on public.driver_availability_slots for delete
using (
  driver_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and coalesce(p.role, 'driver') = 'driver'
      and coalesce(p.is_approved, false) = true
  )
);

drop policy if exists "Drivers can view available or assigned orders" on public.orders;
create policy "Drivers can view available or assigned orders" on public.orders for select
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'driver'
      and coalesce(p.is_approved, false) = true
  )
  and
  (status = 'pending' or driver_id = auth.uid())
);

drop policy if exists "Restaurants can create orders for own branches" on public.orders;
create policy "Restaurants can create orders for own branches" on public.orders for insert
with check (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'restaurant'
      and coalesce(p.is_approved, false) = true
  )
  and exists (
    select 1
    from public.branches b
    where b.id = orders.branch_id
      and b.restaurant_id = auth.uid()
  )
);
