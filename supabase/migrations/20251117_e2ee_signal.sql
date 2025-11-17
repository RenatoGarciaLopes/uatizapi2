-- E2EE (Signal/X3DH + Double Ratchet) - Esquema mínimo
-- Tabelas de dispositivos, bundles (públicos), one-time prekeys e mensagens cifradas.

-- Extensões úteis
create extension if not exists pgcrypto;

-- Dispositivos por usuário
create table if not exists public.e2ee_devices (
  device_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_name text not null,
  registration_id int4 not null,
  created_at timestamptz not null default now(),
  unique (user_id, device_name)
);

-- Bundle público (sem chaves privadas)
create table if not exists public.e2ee_device_bundles (
  device_id uuid primary key references public.e2ee_devices(device_id) on delete cascade,
  identity_key_public bytea not null,                 -- Curve25519 pub
  signed_prekey_id int4 not null,
  signed_prekey_public bytea not null,
  signed_prekey_signature bytea not null,
  one_time_prekeys_remaining int4 not null default 0,
  updated_at timestamptz not null default now()
);

-- One-Time PreKeys públicos
create table if not exists public.e2ee_onetime_prekeys (
  id bigserial primary key,
  device_id uuid not null references public.e2ee_devices(device_id) on delete cascade,
  prekey_id int4 not null,
  prekey_public bytea not null,
  consumed boolean not null default false,
  created_at timestamptz not null default now(),
  unique (device_id, prekey_id)
);

-- Mensagens cifradas (opacas para o servidor)
create table if not exists public.e2ee_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null,
  sender_user_id uuid not null references auth.users(id) on delete set null,
  sender_device_id uuid not null references public.e2ee_devices(device_id) on delete set null,
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  recipient_device_id uuid not null references public.e2ee_devices(device_id) on delete cascade,
  is_prekey boolean not null default false,           -- true para prekey message (X3DH)
  msg_type smallint not null default 1,               -- 1=text, 2=attachment, etc. (metadado não sensível)
  ciphertext bytea not null,                          -- envelope Signal serializado
  created_at timestamptz not null default now(),
  delivered_at timestamptz
);

-- Habilita RLS
alter table public.e2ee_devices enable row level security;
alter table public.e2ee_device_bundles enable row level security;
alter table public.e2ee_onetime_prekeys enable row level security;
alter table public.e2ee_messages enable row level security;

-- Políticas
-- Devices: proprietário pode tudo; ninguém mais.
drop policy if exists e2ee_devices_owner_rw on public.e2ee_devices;
create policy e2ee_devices_owner_rw
on public.e2ee_devices
as permissive
for all
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- Bundles: leitura pública; escrita somente pelo dono do device (via user_id no join)
drop policy if exists e2ee_bundles_public_read on public.e2ee_device_bundles;
create policy e2ee_bundles_public_read
on public.e2ee_device_bundles
as permissive
for select
to authenticated
using (true);

drop policy if exists e2ee_bundles_owner_write on public.e2ee_device_bundles;
create policy e2ee_bundles_owner_write
on public.e2ee_device_bundles
as permissive
for all
to authenticated
using (
  exists (
    select 1 from public.e2ee_devices d
    where d.device_id = e2ee_device_bundles.device_id
      and d.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.e2ee_devices d
    where d.device_id = e2ee_device_bundles.device_id
      and d.user_id = auth.uid()
  )
);

-- One-time prekeys: leitura somente via RPC transacional; escrita só pelo dono.
drop policy if exists e2ee_prekeys_owner_write on public.e2ee_onetime_prekeys;
create policy e2ee_prekeys_owner_write
on public.e2ee_onetime_prekeys
as permissive
for all
to authenticated
using (
  exists (
    select 1 from public.e2ee_devices d
    where d.device_id = e2ee_onetime_prekeys.device_id
      and d.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.e2ee_devices d
    where d.device_id = e2ee_onetime_prekeys.device_id
      and d.user_id = auth.uid()
  )
);

-- Mensagens cifradas: remetente ou destinatário pode ver; inserção restrita ao remetente autenticado
drop policy if exists e2ee_msgs_read on public.e2ee_messages;
create policy e2ee_msgs_read
on public.e2ee_messages
as permissive
for select
to authenticated
using (
  sender_user_id = auth.uid() or recipient_user_id = auth.uid()
);

drop policy if exists e2ee_msgs_insert_sender on public.e2ee_messages;
create policy e2ee_msgs_insert_sender
on public.e2ee_messages
as permissive
for insert
to authenticated
with check (sender_user_id = auth.uid());

drop policy if exists e2ee_msgs_update_delivered on public.e2ee_messages;
create policy e2ee_msgs_update_delivered
on public.e2ee_messages
as permissive
for update
to authenticated
using (recipient_user_id = auth.uid())
with check (recipient_user_id = auth.uid());

-- RPC para reservar/consumir uma One-Time PreKey (transacional, evita corrida)
create or replace function public.reserve_onetime_prekey(target_device uuid)
returns table(prekey_id int4, prekey_public bytea)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with sel as (
    select id, prekey_id, prekey_public
    from public.e2ee_onetime_prekeys
    where device_id = target_device and consumed = false
    order by id
    limit 1
    for update skip locked
  )
  update public.e2ee_onetime_prekeys p
    set consumed = true
  from sel
  where p.id = sel.id
  returning p.prekey_id, p.prekey_public;
end;
$$;

-- Permissão para qualquer autenticado usar a função (sem expor select direto na tabela)
revoke all on function public.reserve_onetime_prekey(uuid) from public;
grant execute on function public.reserve_onetime_prekey(uuid) to authenticated;


