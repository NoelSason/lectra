create or replace function public.risc_enforce_signin_block(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid;
  blocked boolean;
begin
  uid := (event->>'user_id')::uuid;

  select signin_blocked
    into blocked
  from public.risc_account_flags
  where user_id = uid;

  if blocked is true then
    return jsonb_build_object(
      'error', jsonb_build_object(
        'http_code', 403,
        'message', 'This account is temporarily disabled for security reasons. Please contact support if you believe this is a mistake.'
      )
    );
  end if;

  return event;
exception
  when others then
    return event;
end;
$$;

grant execute on function public.risc_enforce_signin_block(jsonb) to supabase_auth_admin;
revoke execute on function public.risc_enforce_signin_block(jsonb) from public, anon, authenticated;
grant select on public.risc_account_flags to supabase_auth_admin;
