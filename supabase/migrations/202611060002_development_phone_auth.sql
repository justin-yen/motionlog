-- Development-only SMS hook. Supabase bypasses this hook for configured test
-- phone numbers. Every real SMS attempt is rejected so development cannot
-- accidentally create carrier charges or silently discard an OTP.
create or replace function public.reject_real_sms(event jsonb)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'error', jsonb_build_object(
      'http_code', 400,
      'message', 'Only configured PT Tracker test phone numbers are available.'
    )
  );
$$;

grant usage on schema public to supabase_auth_admin;
grant execute on function public.reject_real_sms(jsonb) to supabase_auth_admin;
revoke execute on function public.reject_real_sms(jsonb) from authenticated, anon, public;
