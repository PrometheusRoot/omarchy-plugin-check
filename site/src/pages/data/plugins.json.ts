// The index page's compact search data (src/lib/compact.ts), generated at build time.
import type { APIRoute } from 'astro';
import { siteIndex } from '../../lib/data';

export const GET: APIRoute = () =>
  new Response(JSON.stringify(siteIndex()), { headers: { 'content-type': 'application/json' } });
