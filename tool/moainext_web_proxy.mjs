/**
 * Local CORS proxy so Flutter web on localhost can call production MOAINEXT.
 * Usage: node tool/moainext_web_proxy.mjs
 */
import http from 'node:http';

const TARGET = process.env.MOAINEXT_API_ORIGIN || 'https://moainext.moai-crm.com';
const PORT = Number(process.env.MOAINEXT_WEB_PROXY_PORT || 8787);

function corsHeaders(req) {
  const origin = req.headers.origin || 'http://localhost:5173';
  const requested = req.headers['access-control-request-headers'];
  return {
    'access-control-allow-origin': origin,
    'access-control-allow-credentials': 'true',
    'access-control-allow-methods': 'GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS',
    'access-control-allow-headers':
      requested ||
      'Content-Type,Authorization,X-User-Id,X-Business-Id,X-Package-Code,X-CSRF-Token,X-Store-Token,Idempotency-Key',
    'access-control-expose-headers': 'X-Batch-Meta',
    vary: 'Origin',
  };
}

http
  .createServer(async (req, res) => {
    const cors = corsHeaders(req);
    if (req.method === 'OPTIONS') {
      res.writeHead(204, cors);
      res.end();
      return;
    }
    try {
      const chunks = [];
      for await (const chunk of req) chunks.push(chunk);
      const body = Buffer.concat(chunks);
      const target = new URL(req.url || '/', TARGET);
      const headers = { ...req.headers, host: new URL(TARGET).host };
      delete headers.connection;
      delete headers['content-length'];
      if (body.length) headers['content-length'] = String(body.length);
      const upstream = await fetch(target, {
        method: req.method,
        headers,
        body: ['GET', 'HEAD'].includes(req.method || '') ? undefined : body,
        redirect: 'manual',
      });
      const buf = Buffer.from(await upstream.arrayBuffer());
      const out = { ...cors };
      upstream.headers.forEach((value, key) => {
        if (
          [
            'content-encoding',
            'content-length',
            'transfer-encoding',
            'access-control-allow-origin',
            'access-control-allow-credentials',
            'access-control-allow-headers',
            'access-control-allow-methods',
          ].includes(key)
        ) {
          return;
        }
        out[key] = value;
      });
      out['content-length'] = String(buf.length);
      res.writeHead(upstream.status, out);
      res.end(buf);
    } catch (err) {
      res.writeHead(502, { ...cors, 'content-type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ status: 'E', message: String(err?.message || err) }));
    }
  })
  .listen(PORT, '127.0.0.1', () => {
    console.log(`[moainext-web-proxy] http://127.0.0.1:${PORT} -> ${TARGET}`);
  });
