// Cloudflare Pages Function — POST /api/support
// Validates the contact form and stores the message in KV (binding: SUPPORT_MESSAGES).
export async function onRequestPost({ request, env }) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  const name = String(body.name || "").trim();
  const email = String(body.email || "").trim();
  const message = String(body.message || "").trim();

  if (!name || name.length > 100) return json({ error: "Please enter your name." }, 400);
  if (!email || email.length > 200 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return json({ error: "Please enter a valid email." }, 400);
  }
  if (!message || message.length > 4000) return json({ error: "Please enter a message." }, 400);

  const key = `${Date.now()}-${crypto.randomUUID()}`;
  await env.SUPPORT_MESSAGES.put(key, JSON.stringify({ name, email, message, receivedAt: new Date().toISOString() }));

  return json({ ok: true });
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });
}
