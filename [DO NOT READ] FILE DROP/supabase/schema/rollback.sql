-- DropBridge rollback script
-- Date: 2026-02-25
-- Run in staging first.

begin;

drop table if exists public.uploads;
drop table if exists public.devices;
delete from storage.buckets where id = 'drops';

commit;
