import type { Env } from "./types";
import { handleAuth } from "./auth";
import { handleFiles } from "./files";
import { handleSync } from "./sync";
import { json } from "./util";

export default {
  async fetch(req: Request, env: Env, _ctx: ExecutionContext): Promise<Response> {
    if (req.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "access-control-allow-origin": "*",
          "access-control-allow-headers": "authorization, content-type",
          "access-control-allow-methods": "GET,POST,PUT,OPTIONS",
        },
      });
    }

    const url = new URL(req.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";

    if (path === "/" || path === "/health") {
      return json({ ok: true, service: "inkshelf-api", time: new Date().toISOString() });
    }

    const auth = await handleAuth(req, env, path);
    if (auth) return auth;
    const sync = await handleSync(req, env, path);
    if (sync) return sync;
    const files = await handleFiles(req, env, path);
    if (files) return files;

    return json({ error: "Not Found" }, 404);
  },
};
