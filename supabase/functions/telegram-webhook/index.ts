// The Actra bot's webhook: receives "/start <token>" and the shared contact.
// Deployed without JWT verification (Telegram cannot send one); the secret
// header registered with setWebhook is checked instead.

import { handleWebhookRequest } from '../_shared/http.ts';
import { makeDeps } from '../_shared/supabase_deps.ts';

Deno.serve((req) => handleWebhookRequest(makeDeps, Deno.env.get('TELEGRAM_WEBHOOK_SECRET') ?? '', req));
