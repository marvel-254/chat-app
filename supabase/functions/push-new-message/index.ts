import { createClient } from 'npm:@supabase/supabase-js@2';

type DatabaseWebhook = {
  type: string;
  table: string;
  schema: string;
  record: {
    id: string;
    conversation_id: string;
    sender_id: string;
  };
};

type FirebaseServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

const encoder = new TextEncoder();
let cachedAccessToken: { value: string; expiresAt: number } | null = null;

function encodeBase64Url(value: Uint8Array): string {
  let binary = '';
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

function encodeJson(value: unknown): string {
  return encodeBase64Url(encoder.encode(JSON.stringify(value)));
}

async function firebaseAccessToken(
  account: FirebaseServiceAccount,
): Promise<string> {
  if (cachedAccessToken && cachedAccessToken.expiresAt > Date.now() + 60_000) {
    return cachedAccessToken.value;
  }

  const privateKey = account.private_key
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replaceAll(/\s/g, '');
  const signingKey = await crypto.subtle.importKey(
    'pkcs8',
    Uint8Array.from(atob(privateKey), (character) => character.charCodeAt(0)),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const now = Math.floor(Date.now() / 1000);
  const unsignedJwt = `${encodeJson({ alg: 'RS256', typ: 'JWT' })}.${encodeJson({
    iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  })}`;
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    signingKey,
    encoder.encode(unsignedJwt),
  );
  const assertion = `${unsignedJwt}.${encodeBase64Url(new Uint8Array(signature))}`;
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) throw new Error('Firebase authorization failed.');
  const result = await response.json();
  cachedAccessToken = {
    value: result.access_token,
    expiresAt: Date.now() + Number(result.expires_in) * 1000,
  };
  return cachedAccessToken.value;
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }
  if (
    request.headers.get('x-bro-webhook-secret') !==
      Deno.env.get('PUSH_WEBHOOK_SECRET') ||
    !Deno.env.get('PUSH_WEBHOOK_SECRET')
  ) {
    return new Response('Unauthorized', { status: 401 });
  }

  try {
    const webhook = await request.json() as DatabaseWebhook & {
      record?: { reminder_title?: string };
    };
    const isReminder = webhook.type === 'FRIENDSHIP_REMINDER' ||
      Boolean(webhook.record?.reminder_title);
    if (
      webhook.schema !== 'public' ||
      webhook.table !== 'messages' || !webhook.record?.id ||
      !webhook.record.conversation_id ||
      (!isReminder && !webhook.record.sender_id)
    ) {
      return Response.json({ ignored: true });
    }

    const encodedServiceAccount =
      Deno.env.get('FIREBASE_SERVICE_ACCOUNT_B64') ?? '';
    const serviceAccount = JSON.parse(
      atob(encodedServiceAccount),
    ) as FirebaseServiceAccount;
    if (
      !serviceAccount.project_id || !serviceAccount.client_email ||
      !serviceAccount.private_key
    ) {
      throw new Error('Firebase service account is not configured.');
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    // Messages go to everyone except the sender; a friendship reminder is
    // shared by both friends, so it goes to all participants.
    let participantsQuery = supabase
      .from('conversation_participants')
      .select('user_id')
      .eq('conversation_id', webhook.record.conversation_id);
    if (!isReminder && webhook.record.sender_id) {
      participantsQuery = participantsQuery.neq('user_id', webhook.record.sender_id);
    }
    const { data: participants, error: participantError } = await participantsQuery;
    if (participantError) throw participantError;
    const recipients = (participants ?? []).map((item) => item.user_id);
    if (recipients.length === 0) return Response.json({ sent: 0 });

    const { data: devices, error: deviceError } = await supabase
      .from('push_tokens')
      .select('token, user_id')
      .not('token', 'is', null)
      .in('user_id', recipients);
    if (deviceError) throw deviceError;
    if (!devices?.length) return Response.json({ sent: 0 });

    const accessToken = await firebaseAccessToken(serviceAccount);
    const results = await Promise.all(devices.map(async (device) => {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: device.token,
              // A lock-screen notification should not contain plaintext,
              // ciphertext, or the sender's identity.
              notification: isReminder
                ? { title: 'BRO', body: 'A friendship anniversary is today.' }
                : { title: 'BRO', body: 'You have a new message.' },
              data: {
                conversation_id: webhook.record.conversation_id,
                message_id: webhook.record.id,
                recipient_user_id: device.user_id,
                ...(isReminder ? { kind: 'friendship_reminder' } : {}),
              },
              android: { priority: 'HIGH' },
            },
          }),
        },
      );
      if (!response.ok) {
        const result = await response.json().catch(() => ({}));
        const details: { errorCode?: string }[] = Array.isArray(result?.error?.details)
          ? result.error.details : [];
        if (details.some((entry) => entry?.errorCode === 'UNREGISTERED')) {
          await supabase
            .from('push_tokens')
            .delete()
            .eq('token', device.token)
            .eq('user_id', device.user_id);
          return { ok: false, removed: true };
        }
        console.error('Firebase push delivery failed:', result?.error?.status);
        return { ok: false };
      }
      return { ok: true };
    }));

    return Response.json({ sent: results.filter((result) => result.ok).length });
  } catch (error) {
    console.error('Message push handler failed:', error);
    return Response.json({ error: 'Could not send message notification.' }, {
      status: 500,
    });
  }
});
