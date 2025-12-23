alter table public.profiles
  alter column role set default 'driver';

update public.profiles
set role = 'driver'
where role is null;

alter table public.drivers_profiles enable row level security;

grant select on public.drivers_profiles to authenticated;

drop policy if exists "Drivers can view own driver profile" on public.drivers_profiles;
drop policy if exists "Drivers can insert own driver profile" on public.drivers_profiles;
drop policy if exists "Drivers can update own driver profile" on public.drivers_profiles;
drop policy if exists "Admins can view all driver profiles" on public.drivers_profiles;

create policy "Drivers can view own driver profile" on public.drivers_profiles for select
using (
  id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and coalesce(p.role, 'driver') = 'driver'
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
  )
)
with check (
  id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and coalesce(p.role, 'driver') = 'driver'
  )
);

create policy "Admins can view all driver profiles" on public.drivers_profiles for select
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  )
);
