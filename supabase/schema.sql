-- RuangRent schema. Run in Supabase SQL Editor.
create extension if not exists pgcrypto;
create type public.user_role as enum ('tenant','landlord','admin');
create type public.booking_status as enum ('pending','approved','rejected','cancelled');
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null default '',
 role public.user_role not null default 'tenant',
 phone text,
 created_at timestamptz not null default now()
);
create table public.rooms (
 id uuid primary key default gen_random_uuid(),
 landlord_id uuid not null references public.profiles(id) on delete cascade,
 title text not null check (char_length(title) between 3 and 120),
 description text not null default '',
 location text not null,
 monthly_rent numeric(12,2) not null check (monthly_rent > 0),
 image_url text,
 available boolean not null default true,
 created_at timestamptz not null default now()
);
create table public.bookings (
 id uuid primary key default gen_random_uuid(),
 room_id uuid not null references public.rooms(id) on delete cascade,
 tenant_id uuid not null references public.profiles(id) on delete cascade,
 message text not null default '',
 status public.booking_status not null default 'pending',
 created_at timestamptz not null default now(),
 unique(room_id,tenant_id)
);
create index rooms_landlord_idx on public.rooms(landlord_id);
create index bookings_room_idx on public.bookings(room_id);
create index bookings_tenant_idx on public.bookings(tenant_id);

-- Never trust a client-supplied role; every newly registered user starts as tenant.
create or replace function public.new_profile() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 insert into public.profiles(id,full_name,role)
 values(new.id, coalesce(new.raw_user_meta_data->>'full_name',''), 'tenant');
 return new;
end;$$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.new_profile();

-- Security definer avoids recursive policies when checking roles.
create or replace function public.current_role() returns public.user_role language sql stable security definer set search_path = '' as $$
 select role from public.profiles where id = (select auth.uid())
$$;
revoke all on function public.current_role() from public;
grant execute on function public.current_role() to authenticated;

create or replace function public.room_owner(p_room uuid) returns uuid language sql stable security definer set search_path = '' as $$
 select landlord_id from public.rooms where id=p_room
$$;
revoke all on function public.room_owner(uuid) from public;
grant execute on function public.room_owner(uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.bookings enable row level security;

create policy "Own or admin profile read" on public.profiles for select to authenticated
 using (id=(select auth.uid()) or (select public.current_role())='admin');
create policy "Users edit their own non-role fields" on public.profiles for update to authenticated
 using (id=(select auth.uid())) with check (id=(select auth.uid()));
-- Explicit column grants block changing role from browser clients.
revoke all on public.profiles from anon,authenticated;
grant select on public.profiles to authenticated;
grant update(full_name,phone) on public.profiles to authenticated;

-- Explicit grants; RLS remains the authorization boundary.
revoke all on public.rooms from anon,authenticated;
grant select on public.rooms to anon,authenticated;
grant insert,update,delete on public.rooms to authenticated;

create policy "Public listing read" on public.rooms for select to anon,authenticated
 using (available=true or landlord_id=(select auth.uid()) or (select public.current_role())='admin');
create policy "Landlord creates own rooms" on public.rooms for insert to authenticated
 with check (landlord_id=(select auth.uid()) and (select public.current_role())='landlord');
create policy "Landlord/admin updates rooms" on public.rooms for update to authenticated
 using (landlord_id=(select auth.uid()) or (select public.current_role())='admin')
 with check (landlord_id=(select auth.uid()) or (select public.current_role())='admin');
create policy "Landlord/admin deletes rooms" on public.rooms for delete to authenticated
 using (landlord_id=(select auth.uid()) or (select public.current_role())='admin');

create policy "Booking participants read" on public.bookings for select to authenticated
 using (tenant_id=(select auth.uid()) or (select public.room_owner(room_id))=(select auth.uid()) or (select public.current_role())='admin');
create policy "Tenants request rooms" on public.bookings for insert to authenticated
 with check (tenant_id=(select auth.uid()) and (select public.current_role())='tenant' and status='pending'
 and exists(select 1 from public.rooms where id=room_id and available=true));
-- Restrict status changes to separate RPCs; no direct booking updates or deletes granted to clients.
revoke all on public.bookings from anon,authenticated;
grant select,insert on public.bookings to authenticated;

create or replace function public.set_booking_status(p_booking uuid,p_status public.booking_status)
returns void language plpgsql security definer set search_path = '' as $$
declare b public.bookings%rowtype;
begin
 if p_status not in ('approved','rejected','cancelled') then raise exception 'Invalid status'; end if;
 select * into b from public.bookings where id=p_booking for update;
 if not found then raise exception 'Booking not found'; end if;
 if p_status='cancelled' then
   if b.tenant_id <> (select auth.uid()) or b.status <> 'pending' then raise exception 'Not allowed'; end if;
 else
   if (select public.room_owner(b.room_id))<>(select auth.uid())
      and coalesce((select public.current_role())::text,'')<>'admin' then raise exception 'Not allowed'; end if;
   if b.status <> 'pending' then raise exception 'Only pending bookings can be decided'; end if;
 end if;
 update public.bookings set status=p_status where id=p_booking;
end;$$;
revoke all on function public.set_booking_status(uuid,public.booking_status) from public;
grant execute on function public.set_booking_status(uuid,public.booking_status) to authenticated;

-- Landlord promotion is admin-mediated, never a public signup option.
create or replace function public.set_user_role(p_user uuid,p_role public.user_role)
returns void language plpgsql security definer set search_path = '' as $$
begin
 if (select public.current_role()) <> 'admin' then raise exception 'Admin only'; end if;
 if p_user=(select auth.uid()) then raise exception 'Cannot change own role'; end if;
 if p_role='admin' then raise exception 'Admin elevation requires manual database action'; end if;
 update public.profiles set role=p_role where id=p_user;
end;$$;
revoke all on function public.set_user_role(uuid,public.user_role) from public;
grant execute on function public.set_user_role(uuid,public.user_role) to authenticated;

-- First administrator: after signing up, replace UUID with user id from Authentication > Users.
-- update public.profiles set role='admin' where id='REPLACE-WITH-USER-UUID';
-- Promote landlords: Admin dashboard, or SQL: update public.profiles set role='landlord' where id='UUID';
