# VPS proxy deployment (Ubuntu 24.04)

The proxy routes the existing Supabase API through a server reachable by your administrators. No database migration or account recreation is required.

1. Provision a VPS that can reach `https://iguotkyyjatilbzunvsw.supabase.co/auth/v1/health` and is reachable by your administrators.
2. Point an HTTPS hostname, for example `api.example.com`, to the VPS IP. Test the hostname from the affected administrator's connection.
3. Install Nginx and Certbot: `sudo apt update && sudo apt install -y nginx certbot python3-certbot-nginx`.
4. Copy `proxy/nginx.conf` to `/etc/nginx/sites-available/admin-stability`, replacing `api.example.com` with the real hostname. First comment out the 443 server block and configure HTTP only; obtain the certificate using `sudo certbot certonly --nginx -d api.example.com`; restore the 443 block.
5. Enable: `sudo ln -s /etc/nginx/sites-available/admin-stability /etc/nginx/sites-enabled/admin-stability`; run `sudo nginx -t && sudo systemctl reload nginx`.
6. Check from the administrator's device: `https://api.example.com/auth/v1/health`. A JSON or API response confirms network connectivity.
7. Set `SUPABASE_PROXY_URL:'https://api.example.com'` in both `config.js` and `public/config.js`, then increment the cache version in both index files. The app will use the proxy as its API endpoint.

Security: HTTPS is required; never expose the Supabase service_role key to the browser or GitHub. This proxy forwards the public anon key and user JWT. Consider firewall and request-rate limits. Configure Supabase Auth redirect URLs for your GitHub Pages domain if using OAuth or email links. This is a template, not an already deployed VPS.
