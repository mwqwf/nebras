import { readFileSync } from 'node:fs';
import { GoogleAuth } from 'google-auth-library';
const sa = JSON.parse(readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS, 'utf8'));
const auth = new GoogleAuth({ credentials: sa, scopes: ['https://www.googleapis.com/auth/cloud-platform'] });
const client = await auth.getClient();
const tok = await client.getAccessToken();
const resp = await fetch(`https://firestore.googleapis.com/v1/projects/${sa.project_id}/databases`, {
  headers: { Authorization: `Bearer ${tok.token}` }
});
const body = await resp.json();
console.log(JSON.stringify(body, null, 2));
