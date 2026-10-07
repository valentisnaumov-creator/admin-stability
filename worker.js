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

    return env.ASSETS.fetch(request);
  }
};
