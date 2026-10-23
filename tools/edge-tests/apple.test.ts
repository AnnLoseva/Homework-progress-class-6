// Unit tests for the Apple revocation helper used by the delete-account Edge Function.
// Run: node --experimental-strip-types --test tools/edge-tests/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createVerify } from 'node:crypto';
import { makeClientSecret, readAppleConfig, revokeAppleAuthorization } from '../../supabase/functions/delete-account/apple.ts';

// A throwaway key generated for this test run only.
const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const config = {
  teamId: 'TEAMID1234',
  keyId: 'KEYID12345',
  clientId: 'org.example.woodland-study',
  privateKeyPem: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
};

const decode = (part: string) => JSON.parse(Buffer.from(part, 'base64url').toString('utf8'));

test('client secret is a valid ES256 JWT with Apple claims', async () => {
  const jwt = await makeClientSecret(config, Date.UTC(2026, 9, 22));
  const [header, claims, signature] = jwt.split('.');
  assert.deepEqual(decode(header), { alg: 'ES256', kid: 'KEYID12345', typ: 'JWT' });
  const body = decode(claims);
  assert.equal(body.iss, 'TEAMID1234');
  assert.equal(body.sub, 'org.example.woodland-study');
  assert.equal(body.aud, 'https://appleid.apple.com');
  assert.equal(body.exp - body.iat, 300);

  const verifier = createVerify('SHA256');
  verifier.update(`${header}.${claims}`);
  assert.ok(verifier.verify({ key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')));
});

test('a PEM with escaped newlines (as stored in secrets) still works', async () => {
  const escaped = { ...config, privateKeyPem: config.privateKeyPem.replace(/\n/g, '\\n') };
  assert.match(await makeClientSecret(escaped), /^[\w-]+\.[\w-]+\.[\w-]+$/);
});

test('missing secrets disable revocation instead of failing', () => {
  assert.equal(readAppleConfig(() => undefined), null);
  assert.equal(readAppleConfig((n) => (n === 'APPLE_TEAM_ID' ? 'x' : undefined)), null);
});

test('revocation exchanges the code, then revokes the refresh token', async () => {
  const calls: { url: string; body: URLSearchParams }[] = [];
  const fakeFetch = (async (url: string, init: RequestInit) => {
    const body = init.body as URLSearchParams;
    calls.push({ url, body });
    if (url.endsWith('/auth/token')) return new Response(JSON.stringify({ refresh_token: 'r-token' }), { status: 200 });
    return new Response('', { status: 200 });
  }) as unknown as typeof fetch;

  assert.equal(await revokeAppleAuthorization(config, 'auth-code', fakeFetch), true);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].body.get('code'), 'auth-code');
  assert.equal(calls[0].body.get('grant_type'), 'authorization_code');
  assert.equal(calls[1].body.get('token'), 'r-token');
  assert.equal(calls[1].body.get('token_type_hint'), 'refresh_token');
});

test('revocation failures return false and never throw', async () => {
  const failing = (async () => new Response('{"error":"invalid_grant"}', { status: 400 })) as unknown as typeof fetch;
  assert.equal(await revokeAppleAuthorization(config, 'expired', failing), false);
  const throwing = (async () => { throw new Error('offline'); }) as unknown as typeof fetch;
  assert.equal(await revokeAppleAuthorization(config, 'code', throwing), false);
});
