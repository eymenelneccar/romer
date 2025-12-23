create or replace function public.admin_set_user_role(p_user_id uuid, p_role text)
returns table (id uuid, role text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_role not in ('admin', 'restaurant', 'driver') then
    raise exception 'Invalid role';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
  ) then
    raise exception 'Only admins can change role';
  end if;

  return query
  update public.profiles
  set role = p_role
  where public.profiles.id = p_user_id
  returning public.profiles.id, public.profiles.role;
end;
$$;

grant execute on function public.admin_set_user_role(uuid, text) to authenticated;

