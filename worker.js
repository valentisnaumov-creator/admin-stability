export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/api/login") {
      if (request.method !== "POST") {
        return Response.json({ error: "METHOD_NOT_ALLOWED" }, { status: 405 });
      }
      try {
        const body = await request.json();
        const email = String(body?.email || "").trim();
        const password = String(body?.password || "");
        if (!email || !password) {
          return Response.json({ error: "Введите почту и пароль" }, { status: 400 });
        }

        const auth = await fetch("https://iguotkyyjatilbzunvsw.supabase.co/auth/v1/token?grant_type=password", {
          method: "POST",
          headers: {
            "apikey": "sb_publishable_sK5sa-kr558LAdQLxf_lhw_ENZ9z8kA",
            "Content-Type": "application/json"
          },
          body: JSON.stringify({ email, password })
        });

        const payload = await auth.text();
        return new Response(payload, {
          status: auth.status,
          headers: {
            "Content-Type": "application/json",
            "Cache-Control": "no-store"
          }
        });
      } catch {
        return Response.json({ error: "Не удалось выполнить вход" }, { status: 500 });
      }
    }

    if (url.pathname.startsWith("/api/supabase/")) {
      const targetPath = url.pathname.slice("/api/supabase".length);
      if (!targetPath.startsWith("/rest/v1/") && !targetPath.startsWith("/auth/v1/") && !targetPath.startsWith("/storage/v1/")) {
        return Response.json({ error: "NOT_ALLOWED" }, { status: 403 });
      }
      const target = new URL("https://iguotkyyjatilbzunvsw.supabase.co" + targetPath + url.search);
      const headers = new Headers(request.headers);
      headers.set("apikey", "sb_publishable_sK5sa-kr558LAdQLxf_lhw_ENZ9z8kA");
      headers.delete("host");
      headers.delete("origin");
      headers.delete("referer");
      const upstream = await fetch(target, {
        method: request.method,
        headers,
        body: ["GET","HEAD"].includes(request.method) ? undefined : request.body,
        redirect: "follow"
      });
      const outHeaders = new Headers(upstream.headers);
      outHeaders.set("Cache-Control","no-store");
      return new Response(upstream.body,{status:upstream.status,headers:outHeaders});
    }

    return env.ASSETS.fetch(request);
  }
};
