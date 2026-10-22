// Sign in with Apple token revocation (App Store Review Guideline 5.1.1(v)).
//
// No imports on purpose: this file runs unchanged on Deno (Edge Functions) and on Node's
// type stripping (tools/edge-tests), so it can be unit-tested without Deno.

export interface AppleConfig {
  teamId: string;     // Apple Developer Team ID
  keyId: string;      // Key ID of the "Sign in with Apple" private key
  clientId: string;   // the app's bundle identifier
  privateKeyPem: string; // contents of the .p8 file (PKCS#8 PEM)
}

const encoder = new TextEncoder();

function base64url(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToPkcs8(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\\n/g, '')
    .replace(/\s+/g, '');
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/** ES256 client secret JWT, valid for 5 minutes (Apple allows up to 6 months). */
export async function makeClientSecret(config: AppleConfig, now = Date.now()): Promise<string> {
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToPkcs8(config.privateKeyPem),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
  const iat = Math.floor(now / 1000);
  const header = { alg: 'ES256', kid: config.keyId, typ: 'JWT' };
  const claims = { iss: config.teamId, iat, exp: iat + 300, aud: 'https://appleid.apple.com', sub: config.clientId };
  const signingInput =
    `${base64url(encoder.encode(JSON.stringify(header)))}.${base64url(encoder.encode(JSON.stringify(claims)))}`;
  // WebCrypto returns the raw r||s signature, which is exactly the JWS ES256 format.
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, encoder.encode(signingInput)),
  );
  return `${signingInput}.${base64url(signature)}`;
}

export function readAppleConfig(env: (name: string) => string | undefined): AppleConfig | null {
  const teamId = env('APPLE_TEAM_ID');
  const keyId = env('APPLE_KEY_ID');
  const clientId = env('APPLE_CLIENT_ID');
  const privateKeyPem = env('APPLE_PRIVATE_KEY');
  if (!teamId || !keyId || !clientId || !privateKeyPem) return null;
  return { teamId, keyId, clientId, privateKeyPem };
}

/**
 * Exchanges a fresh authorization code for a refresh token and revokes it, which removes
 * the app from the user's "Sign in with Apple" list. Returns false (never throws) so a
 * revocation problem never blocks deleting the account's data.
 */
export async function revokeAppleAuthorization(
  config: AppleConfig,
  authorizationCode: string,
  fetchImpl: typeof fetch = fetch,
): Promise<boolean> {
  try {
    const clientSecret = await makeClientSecret(config);
    const tokenResponse = await fetchImpl('https://appleid.apple.com/auth/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: config.clientId,
        client_secret: clientSecret,
        code: authorizationCode,
        grant_type: 'authorization_code',
      }),
    });
    if (!tokenResponse.ok) return false;
    const tokens = await tokenResponse.json() as { refresh_token?: string; access_token?: string };
    const token = tokens.refresh_token ?? tokens.access_token;
    if (!token) return false;

    const revokeResponse = await fetchImpl('https://appleid.apple.com/auth/revoke', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: config.clientId,
        client_secret: clientSecret,
        token,
        token_type_hint: tokens.refresh_token ? 'refresh_token' : 'access_token',
      }),
    });
    return revokeResponse.ok;
  } catch {
    return false;
  }
}
