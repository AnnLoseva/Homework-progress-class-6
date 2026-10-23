// delete-account — the only code that uses the service-role key, and it runs on Supabase's
// servers, never in the app.
//
// 1. Verifies the caller's access token with Supabase Auth (the user id comes from the
//    token, never from the request body).
// 2. Optionally revokes the Sign in with Apple authorization (if APPLE_* secrets are set and
//    the app sent a fresh authorization code).
// 3. Removes the user's files from the `student-private` bucket.
// 4. Deletes the auth user. profiles, class_enrollments, lesson_subscriptions,
//    lesson_progress and join attempts are removed by ON DELETE CASCADE.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { readAppleConfig, revokeAppleAuthorization } from './apple.ts';

const PRIVATE_BUCKET = 'student-private';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const authorization = request.headers.get('Authorization') ?? '';
  const accessToken = authorization.startsWith('Bearer ') ? authorization.slice('Bearer '.length) : '';
  if (!accessToken) return json({ error: 'unauthorized' }, 401);

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) return json({ error: 'server_misconfigured' }, 500);

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await admin.auth.getUser(accessToken);
  if (userError || !userData?.user) return json({ error: 'unauthorized' }, 401);
  const userId = userData.user.id;

  let body: { apple_authorization_code?: unknown } = {};
  try {
    body = await request.json();
  } catch {
    // An empty body is fine.
  }

  let appleTokenRevoked = false;
  const appleConfig = readAppleConfig((name) => Deno.env.get(name));
  if (appleConfig && typeof body.apple_authorization_code === 'string' && body.apple_authorization_code.length < 4096) {
    appleTokenRevoked = await revokeAppleAuthorization(appleConfig, body.apple_authorization_code);
  }

  // Remove private files page by page. Paths are always "<user id>/…", so the prefix is
  // derived from the verified token.
  for (;;) {
    const { data: files, error: listError } = await admin.storage
      .from(PRIVATE_BUCKET)
      .list(userId, { limit: 100 });
    if (listError) return json({ error: 'storage_cleanup_failed' }, 500);
    if (!files || files.length === 0) break;
    const { error: removeError } = await admin.storage
      .from(PRIVATE_BUCKET)
      .remove(files.map((file) => `${userId}/${file.name}`));
    if (removeError) return json({ error: 'storage_cleanup_failed' }, 500);
    if (files.length < 100) break;
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) return json({ error: 'delete_failed' }, 500);

  return json({ deleted: true, apple_token_revoked: appleTokenRevoked });
});
