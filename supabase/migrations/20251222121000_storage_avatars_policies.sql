insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update
set
  name = excluded.name,
  public = excluded.public;

alter table storage.objects enable row level security;

grant select, insert, update, delete on table storage.objects to authenticated;
grant select on table storage.objects to anon;

drop policy if exists "Users can upload their own avatars" on storage.objects;
drop policy if exists "Users can update their own avatars" on storage.objects;
drop policy if exists "Users can delete their own avatars" on storage.objects;
drop policy if exists "Users can read their own avatars" on storage.objects;
drop policy if exists "Public can read avatars" on storage.objects;

create policy "Users can upload their own avatars" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'avatars'
  and name like (auth.uid()::text || '/%')
);

create policy "Users can update their own avatars" on storage.objects
for update to authenticated
using (
  bucket_id = 'avatars'
  and name like (auth.uid()::text || '/%')
)
with check (
  bucket_id = 'avatars'
  and name like (auth.uid()::text || '/%')
);

create policy "Users can delete their own avatars" on storage.objects
for delete to authenticated
using (
  bucket_id = 'avatars'
  and name like (auth.uid()::text || '/%')
);

create policy "Users can read their own avatars" on storage.objects
for select to authenticated
using (
  bucket_id = 'avatars'
  and name like (auth.uid()::text || '/%')
);

create policy "Public can read avatars" on storage.objects
for select to anon
using (
  bucket_id = 'avatars'
);
