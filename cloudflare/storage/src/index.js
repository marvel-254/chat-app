const MAX_ATTACHMENT_BYTES = 20 * 1024 * 1024;
const MAX_BACKGROUND_BYTES = 10 * 1024 * 1024;
const MAX_KEY_LENGTH = 512;
const IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/gif']);
const INLINE_TYPES = new Set([...IMAGE_TYPES, 'video/mp4', 'video/webm', 'video/quicktime', 'application/pdf']);
const DANGEROUS_TYPES = new Set(['text/html', 'image/svg+xml', 'application/xhtml+xml', 'text/xml', 'application/xml']);

function cors(headers = {}) {
  return {
    ...headers,
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Max-Age': '86400',
  };
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: cors({ 'Content-Type': 'application/json; charset=utf-8' }),
  });
}

function safeSegment(value) {
  return value.replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 120) || 'file';
}

async function userFor(request, env) {
  const authorization = request.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) return null;
  const response = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: authorization },
  });
  if (!response.ok) return null;
  const user = await response.json();
  return typeof user.id === 'string' ? user : null;
}

async function isConversationMember(user, conversationId, env, authorization) {
  if (!/^[0-9a-f-]{36}$/i.test(conversationId)) return false;
  const url = new URL(`${env.SUPABASE_URL}/rest/v1/conversation_participants`);
  url.searchParams.set('select', 'conversation_id');
  url.searchParams.set('conversation_id', `eq.${conversationId}`);
  url.searchParams.set('user_id', `eq.${user.id}`);
  const response = await fetch(url, {
    headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: authorization },
  });
  if (!response.ok) return false;
  return (await response.json()).length > 0;
}

function isSafeKey(key) {
  if (!key || key.length > MAX_KEY_LENGTH) return false;
  if (key.includes('..') || key.includes('\\') || key.includes('\0')) return false;
  const segments = key.split('/');
  return segments.length >= 2 && segments.every((segment) => segment.length > 0);
}

function safeContentType(value) {
  const type = (value ?? 'application/octet-stream').split(';')[0].trim().toLowerCase();
  if (DANGEROUS_TYPES.has(type) || type.startsWith('text/html')) return 'application/octet-stream';
  if (/^[a-z0-9.+-]+\/[a-z0-9.+-]+$/.test(type)) return type;
  return 'application/octet-stream';
}

async function authorizedKey(user, key, env, authorization) {
  if (!isSafeKey(key)) return false;
  const segments = key.split('/');
  if (segments.length === 2 && segments[0] === user.id && /^background\.(jpe?g|png|webp|gif)$/i.test(segments[1])) return true;
  // Any conversation member may sign chat files, not only the uploader.
  if (segments.length >= 3) return isConversationMember(user, segments[0], env, authorization);
  return false;
}

async function sign(key, expires, secret) {
  const encoder = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('HMAC', cryptoKey, encoder.encode(`${key}\n${expires}`));
  return [...new Uint8Array(signature)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function constantTimeEqual(a, b) {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return mismatch === 0;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors() });

    try {
      if (request.method === 'GET' && url.pathname === '/download') {
        const key = url.searchParams.get('key') ?? '';
        const expires = Number(url.searchParams.get('expires'));
        const signature = url.searchParams.get('sig') ?? '';
        if (!isSafeKey(key)) return json({ error: 'Invalid link.' }, 401);
        if (!Number.isSafeInteger(expires) || expires < Date.now() / 1000 || expires > Date.now() / 1000 + 3600) return json({ error: 'Link expired.' }, 401);
        const expected = await sign(key, expires, env.URL_SIGNING_SECRET);
        if (!await constantTimeEqual(signature, expected)) return json({ error: 'Invalid link.' }, 401);
        const object = await env.CHAT_STORAGE.get(key);
        if (!object) return json({ error: 'File not found.' }, 404);
        const contentType = safeContentType(object.httpMetadata?.contentType);
        const filename = safeSegment(key.split('/').pop() ?? 'file');
        const disposition = INLINE_TYPES.has(contentType) ? 'inline' : 'attachment';
        const headers = new Headers(cors({
          'Content-Type': contentType,
          'Content-Disposition': `${disposition}; filename="${filename}"`,
          'Cache-Control': 'private, max-age=300',
          'Content-Length': String(object.size),
          'X-Content-Type-Options': 'nosniff',
          'Content-Security-Policy': "default-src 'none'; img-src 'self' data:; media-src 'self'; style-src 'none'; script-src 'none'",
        }));
        return new Response(object.body, { headers });
      }

      const user = await userFor(request, env);
      if (!user) return json({ error: 'Sign in to access files.' }, 401);
      const authorization = request.headers.get('Authorization');

      if (request.method === 'POST' && url.pathname === '/upload/background') {
        const contentType = (request.headers.get('Content-Type') ?? '').split(';')[0].toLowerCase();
        if (!IMAGE_TYPES.has(contentType)) return json({ error: 'Unsupported image type.' }, 415);
        const body = await request.arrayBuffer();
        if (body.byteLength > MAX_BACKGROUND_BYTES) return json({ error: 'Background must be 10 MB or smaller.' }, 413);
        const extension = ({ 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/gif': 'gif' })[contentType];
        const key = `${user.id}/background.${extension}`;
        await env.CHAT_STORAGE.put(key, body, { httpMetadata: { contentType } });
        return json({ path: key });
      }

      if (request.method === 'POST' && url.pathname === '/upload/attachment') {
        const conversationId = url.searchParams.get('conversation') ?? '';
        if (!await isConversationMember(user, conversationId, env, authorization)) return json({ error: 'Not a conversation member.' }, 403);
        const contentType = safeContentType(request.headers.get('Content-Type'));
        const body = await request.arrayBuffer();
        if (body.byteLength > MAX_ATTACHMENT_BYTES) return json({ error: 'Files must be 20 MB or smaller.' }, 413);
        const name = safeSegment(url.searchParams.get('name') ?? 'file');
        const key = `${conversationId}/${user.id}/${crypto.randomUUID()}-${name}`;
        await env.CHAT_STORAGE.put(key, body, { httpMetadata: { contentType } });
        return json({ path: key });
      }

      if (request.method === 'POST' && url.pathname === '/sign') {
        const key = url.searchParams.get('key') ?? '';
        if (!await authorizedKey(user, key, env, authorization)) return json({ error: 'You cannot access this file.' }, 403);
        // Keep files uploaded before the R2 migration accessible from Supabase Storage.
        if (!await env.CHAT_STORAGE.head(key)) {
          const bucket = key.split('/').length === 2 ? 'chat-backgrounds' : 'chat-files';
          const objectPath = key.split('/').map(encodeURIComponent).join('/');
          const legacy = await fetch(`${env.SUPABASE_URL}/storage/v1/object/sign/${bucket}/${objectPath}`, {
            method: 'POST',
            headers: {
              apikey: env.SUPABASE_ANON_KEY,
              Authorization: authorization,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({ expiresIn: 3600 }),
          });
          if (!legacy.ok) return json({ error: 'File not found.' }, 404);
          const result = await legacy.json();
          const signedURL = result.signedURL ?? result.signedUrl;
          return json({ url: /^https?:\/\//.test(signedURL)
            ? signedURL
            : `${env.SUPABASE_URL}/storage/v1${signedURL}` });
        }
        const expires = Math.floor(Date.now() / 1000) + 3600;
        const sig = await sign(key, expires, env.URL_SIGNING_SECRET);
        return json({ url: `${url.origin}/download?${new URLSearchParams({ key, expires: String(expires), sig })}` });
      }

      return json({ error: 'Not found.' }, 404);
    } catch (error) {
      console.error('Storage request failed', error);
      return json({ error: 'Storage request failed.' }, 500);
    }
  },
};
