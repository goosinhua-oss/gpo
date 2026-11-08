-- 食品工厂 Supabase 数据库初始化
-- 在 Supabase Dashboard > SQL Editor 执行一次。
-- 本方案把原系统完整 DB 对象存入 JSONB，保留现有功能数据结构。

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid,
  role text not null default 'worker' check (role in ('boss','worker')),
  created_at timestamptz not null default now()
);

create table if not exists public.factory_state (
  company_id uuid primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- 新用户注册时自动建立未分配的 worker profile；不会自动获得公司访问权。
create or replace function public.create_factory_profile()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles(id, role) values (new.id, 'worker')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_factory_profile on auth.users;
create trigger on_auth_user_created_factory_profile
after insert on auth.users
for each row execute procedure public.create_factory_profile();

create or replace function public.is_factory_member(target_company uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and company_id = target_company
      and role in ('boss','worker')
  );
$$;

create or replace function public.is_factory_boss(target_company uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and company_id = target_company and role = 'boss'
  );
$$;

alter table public.profiles enable row level security;
alter table public.factory_state enable row level security;

drop policy if exists "profile read own" on public.profiles;
create policy "profile read own" on public.profiles
for select to authenticated using (id = auth.uid());

-- 工厂成员可读取云端资料；只有老板可以新增或修改整份资料。
drop policy if exists "factory members read state" on public.factory_state;
create policy "factory members read state" on public.factory_state
for select to authenticated using (public.is_factory_member(company_id));

drop policy if exists "boss insert state" on public.factory_state;
create policy "boss insert state" on public.factory_state
for insert to authenticated with check (public.is_factory_boss(company_id));

drop policy if exists "boss update state" on public.factory_state;
create policy "boss update state" on public.factory_state
for update to authenticated using (public.is_factory_boss(company_id))
with check (public.is_factory_boss(company_id));

-- 固定本工厂 ID。老板与工人都必须使用同一个 company_id。
-- COMPANY_ID = 11111111-1111-4111-8111-111111111111

-- 第一步：先在网站注册老板账号并验证电邮，然后把下面的老板邮箱改成实际邮箱执行：
-- update public.profiles
-- set company_id = '11111111-1111-4111-8111-111111111111', role = 'boss'
-- where id = (select id from auth.users where email = '老板邮箱@example.com');

-- 第二步：每位工人先在网站注册账号并验证电邮，再逐个执行：
-- update public.profiles
-- set company_id = '11111111-1111-4111-8111-111111111111', role = 'worker'
-- where id = (select id from auth.users where email = '工人邮箱@example.com');

-- 安全提示：不要把 service_role key 放入网站；前端只使用 anon/publishable key。
