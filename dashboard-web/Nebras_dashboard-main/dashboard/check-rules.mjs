/**
 * يعرض القواعد المنشورة حالياً (أحدث release لكل خدمة).
 */
import { getRulesAccessToken } from "./scripts/load-admin-credential.mjs";

const PROJECT_ID = "nebras-9118c";

async function getRuleset(token, rulesetName) {
  const r = await fetch(`https://firebaserules.googleapis.com/v1/${rulesetName}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return r.ok ? r.json() : null;
}

const token = await getRulesAccessToken();
const list = await fetch(
  `https://firebaserules.googleapis.com/v1/projects/${PROJECT_ID}/releases`,
  { headers: { Authorization: `Bearer ${token}` } },
);
const { releases = [] } = await list.json();

for (const rel of releases) {
  const short = rel.name.split("/releases/").pop();
  const rs = await getRuleset(token, rel.rulesetName);
  const content = rs?.source?.files?.[0]?.content || "(empty)";
  const preview = content.slice(0, 200).replace(/\n/g, " ");
  const ok =
    short.startsWith("cloud.firestore") &&
    content.includes("hasDashboardWrite") &&
    content.includes("validFileDoc");
  console.log(`\n=== ${short} ===`);
  console.log("ruleset:", rel.rulesetName);
  console.log("updated:", rel.updateTime);
  if (short.startsWith("cloud.firestore")) {
    console.log("production rules:", ok ? "YES" : "NO (still old/deny-all?)");
  }
  console.log("preview:", preview, "...");
}
