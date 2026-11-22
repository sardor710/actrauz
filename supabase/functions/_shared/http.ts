// The HTTP edges of the two functions. Standard Request/Response only, so
// they run under Deno and under `node --test` alike.

import { claimLogin, handleUpdate, startLogin } from './login_core.ts';
import type { Deps, TelegramUpdate } from './login_core.ts';

// The web build of the app calls telegram-login from a browser.
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

/** POST {action: "start", language} or {action: "claim", token, poll_secret}. */
export async function handleLoginRequest(deps: Deps, req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'bad_request' }, 400);
  }

  try {
    if (body.action === 'start') {
      return json(await startLogin(deps, { language: typeof body.language === 'string' ? body.language : undefined }));
    }
    if (body.action === 'claim') {
      return json(
        await claimLogin(deps, {
          token: typeof body.token === 'string' ? body.token : undefined,
          pollSecret: typeof body.poll_secret === 'string' ? body.poll_secret : undefined,
        }),
      );
    }
    return json({ error: 'bad_request' }, 400);
  } catch (e) {
    console.error('telegram-login failed:', e);
    return json({ error: 'server_error' }, 500);
  }
}

/**
 * The bot webhook. Telegram repeats the secret we registered in a header on
 * every call; anything without it is not Telegram.
 */
export async function handleWebhookRequest(deps: () => Deps, secret: string, req: Request): Promise<Response> {
  if (req.method !== 'POST') return new Response('method not allowed', { status: 405 });
  if (!secret || req.headers.get('X-Telegram-Bot-Api-Secret-Token') !== secret) {
    return new Response('unauthorized', { status: 401 });
  }

  let update: TelegramUpdate;
  try {
    update = await req.json();
  } catch {
    return new Response('bad request', { status: 400 });
  }

  try {
    await handleUpdate(deps(), update);
  } catch (e) {
    // Answer 200 anyway: a failing update must not be redelivered for hours.
    console.error('telegram-webhook failed:', e);
  }
  return new Response('ok');
}
