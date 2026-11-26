// Deletes the signed-in player's account (both app stores require it).
//   POST with the player's JWT -> 200 {status: "deleted"} | 403 {error: "admin_account"} | 401
// The logic is in _shared/delete_account_core.ts.

import { handleDeleteRequest } from '../_shared/http.ts';
import { makeDeleteDeps } from '../_shared/supabase_deps.ts';

Deno.serve((req) => handleDeleteRequest(makeDeleteDeps(), req));
