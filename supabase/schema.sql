-- Run in Supabase SQL Editor on a NEW project.
create extension if not exists pgcrypto;
create table public.profiles(id uuid primary key references auth.users(id) on delete cascade, email text not null, full_name text not null, role text not null default 'employee' check(role in ('admin','employee')), active boolean not null default true, created_at timestamptz not null default now());
create table public.projects(id uuid primary key default gen_random_uuid(), code text not null unique, name text not null, description text, start_date date, due_date date, created_at timestamptz not null default now());
create table public.tasks(id uuid primary key default gen_random_uuid(), project_id uuid not null references public.projects(id), assigned_to uuid not null references public.profiles(id), title text not null, description text, start_date date, due_date date, priority text not null default 'normal' check(priority in ('low','normal','high')), progress integer not null default 0 check(progress between 0 and 100), status text not null default 'todo' check(status in ('todo','progress','blocked','review','done')), created_at timestamptz not null default now());
create table public.task_reports(id uuid primary key default gen_random_uuid(), task_id uuid not null references public.tasks(id), author_id uuid not null default auth.uid() references public.profiles(id), progress integer not null check(progress between 0 and 100), note text not null check(length(trim(note))>0), report_date date not null, status text not null check(status in ('progress','blocked','review')), submitted_at timestamptz not null default now());
create table public.attachments(id uuid primary key default gen_random_uuid(), report_id uuid not null references public.task_reports(id), storage_path text not null unique, file_name text not null, file_size bigint not null check(file_size between 0 and 10485760), mime_type text, created_at timestamptz not null default now());
create table public.notifications(id uuid primary key default gen_random_uuid(), recipient_id uuid not null references public.profiles(id), message text not null, read_at timestamptz, created_at timestamptz not null default now());
create table public.activity_logs(id uuid primary key default gen_random_uuid(), actor_id uuid references public.profiles(id), action text not null, entity_type text not null, entity_id uuid, created_at timestamptz not null default now());
create index tasks_assignee_idx on public.tasks(assigned_to);create index tasks_project_idx on public.tasks(project_id);create index reports_task_idx on public.task_reports(task_id);create index attachments_report_idx on public.attachments(report_id);
-- SECURITY DEFINER helpers avoid recursive profile policies.
create function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.profiles where id=(select auth.uid()) and role='admin' and active)$$;
create function public.is_active() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.profiles where id=(select auth.uid()) and active)$$;
create function public.can_access_task(t uuid) returns boolean language sql stable security definer set search_path='' as $$select public.is_admin() or (public.is_active() and exists(select 1 from public.tasks where id=t and assigned_to=(select auth.uid())))$$;
create function public.can_access_report(r uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.task_reports where id=r and public.can_access_task(task_id))$$;
revoke all on function public.is_admin() from public;revoke all on function public.is_active() from public;revoke all on function public.can_access_task(uuid) from public;revoke all on function public.can_access_report(uuid) from public;
grant execute on function public.is_admin(),public.is_active(),public.can_access_task(uuid),public.can_access_report(uuid) to authenticated;
alter table public.profiles enable row level security;alter table public.projects enable row level security;alter table public.tasks enable row level security;alter table public.task_reports enable row level security;alter table public.attachments enable row level security;alter table public.notifications enable row level security;alter table public.activity_logs enable row level security;
create policy profiles_read on public.profiles for select to authenticated using (public.is_admin() or (id=(select auth.uid()) and public.is_active()));
create policy profiles_admin_update on public.profiles for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy projects_read on public.projects for select to authenticated using(public.is_admin() or (public.is_active() and exists(select 1 from public.tasks where project_id=projects.id and assigned_to=(select auth.uid()))));
create policy projects_admin_insert on public.projects for insert to authenticated with check(public.is_admin());
create policy projects_admin_update on public.projects for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy tasks_read on public.tasks for select to authenticated using(public.is_admin() or (public.is_active() and assigned_to=(select auth.uid())));
create policy tasks_admin_insert on public.tasks for insert to authenticated with check(public.is_admin());
create policy tasks_admin_update on public.tasks for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy reports_read on public.task_reports for select to authenticated using(public.can_access_task(task_id));
create policy reports_employee_insert on public.task_reports for insert to authenticated with check(author_id=(select auth.uid()) and public.is_active() and exists(select 1 from public.tasks where id=task_id and assigned_to=(select auth.uid()) and status<>'done'));
create policy attachments_read on public.attachments for select to authenticated using(public.can_access_report(report_id));
create policy attachments_insert on public.attachments for insert to authenticated with check(public.is_active() and exists(select 1 from public.task_reports r where r.id=report_id and r.author_id=(select auth.uid()) and storage_path like r.task_id::text||'/'||r.id::text||'/%'));
create policy notifications_read on public.notifications for select to authenticated using(public.is_active() and recipient_id=(select auth.uid()));
create policy notifications_update on public.notifications for update to authenticated using(public.is_active() and recipient_id=(select auth.uid())) with check(recipient_id=(select auth.uid()));
create policy activity_logs_admin_read on public.activity_logs for select to authenticated using(public.is_admin());
-- Reports are immutable; trigger updates task progress in the same transaction.
create function public.apply_report() returns trigger language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from public.tasks t where t.id=new.task_id and t.assigned_to=new.author_id and t.status<>'done') then raise exception 'Not assigned or task already completed'; end if;
 update public.tasks set progress=new.progress,status=new.status where id=new.task_id;
 insert into public.activity_logs(actor_id,action,entity_type,entity_id) values(new.author_id,'submitted_report','task_report',new.id);
 return new;end$$;
create trigger on_report_insert after insert on public.task_reports for each row execute function public.apply_report();
-- Private Storage bucket: only assigned employees and admin may read; only report author may upload.
insert into storage.buckets(id,name,public,file_size_limit) values('report-files','report-files',false,10485760) on conflict(id) do update set public=false,file_size_limit=10485760;
create policy report_storage_read on storage.objects for select to authenticated using(bucket_id='report-files' and public.can_access_report((split_part(name,'/',2))::uuid));
create policy report_storage_upload on storage.objects for insert to authenticated with check(bucket_id='report-files' and public.is_active() and exists(select 1 from public.task_reports r where r.id=(split_part(name,'/',2))::uuid and r.task_id::text=split_part(name,'/',1) and r.author_id=(select auth.uid())));
-- IMPORTANT: Create your first admin via Supabase Auth dashboard, then run:
-- insert into public.profiles(id,email,full_name,role) values('<AUTH_USER_UUID>','admin@example.com','Administrator','admin');
