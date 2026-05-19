create table if not exists public.orders (
  id text primary key,
  customer_name text not null default '',
  material text not null default '',
  color text not null default '',
  pvc_meters numeric,
  quantity numeric,
  cut_status text not null default 'Bilinmiyor',
  notes text not null default '',
  cell_highlights jsonb not null default '[]'::jsonb,
  range_notes jsonb not null default '[]'::jsonb,
  order_date timestamptz,
  source_file text not null default '',
  sheet_name text not null default '',
  source_row integer,
  updated_at timestamptz not null default now()
);

alter table public.orders enable row level security;

drop policy if exists "Public read access" on public.orders;
create policy "Public read access"
  on public.orders
  for select
  to authenticated
  using (true);

create index if not exists orders_customer_name_idx on public.orders (customer_name);
create index if not exists orders_order_date_idx on public.orders (order_date desc);
