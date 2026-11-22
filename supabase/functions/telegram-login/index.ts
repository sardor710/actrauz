// Starts and redeems Telegram sign-in attempts for the app.
//   POST {action: "start", language}             -> {token, poll_secret, bot_url, expires_in}
//   POST {action: "claim", token, poll_secret}   -> {status: "pending" | "expired"} | {status: "ok", token_hash, is_new}

import { handleLoginRequest } from '../_shared/http.ts';
import { makeDeps } from '../_shared/supabase_deps.ts';

Deno.serve((req) => handleLoginRequest(makeDeps(), req));
