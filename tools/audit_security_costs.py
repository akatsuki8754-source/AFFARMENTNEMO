#!/usr/bin/env python3
"""
Kotodama 完全セキュリティ + コスト監査スクリプト
すべての設定を「できていない前提」で検証する。
"""
import json, urllib.request, urllib.error, time
from pathlib import Path

cfg = json.loads((Path.home() / ".config/configstore/firebase-tools.json").read_text())
TOKEN = cfg["tokens"]["access_token"]
PROJECT = "kotodama-86a14"
PROJECT_NUM = "286965080942"
BILLING_ACC = "012878-589A17-F1BEDE"

PASS = "✅"
FAIL = "❌"
WARN = "⚠️"

def req(method, url, body=None, with_quota_project=True):
    data = json.dumps(body).encode() if body else (b'' if method == "POST" else None)
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", f"Bearer {TOKEN}")
    if with_quota_project:
        r.add_header("x-goog-user-project", PROJECT)
    if data: r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            text = resp.read()
            try:
                return resp.status, (json.loads(text) if text else {})
            except Exception:
                return resp.status, {"_raw": text[:200].decode("utf-8", errors="ignore")}
    except urllib.error.HTTPError as e:
        body_text = e.read() if e.fp else b""
        try:
            return e.code, json.loads(body_text)
        except Exception:
            return e.code, {"_raw": body_text[:300].decode("utf-8", errors="ignore")}


print("=" * 70)
print("🔍 KOTODAMA SECURITY + COST AUDIT")
print("=" * 70)


# ─── 1. Billing 状態 ───
print("\n[1] Billing & Cost ━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
s, d = req("GET", f"https://cloudbilling.googleapis.com/v1/projects/{PROJECT}/billingInfo", with_quota_project=False)
print(f"  {PASS if d.get('billingEnabled') else FAIL} billingEnabled = {d.get('billingEnabled')}")
print(f"     → linked: {d.get('billingAccountName')}")

# Budget
s, d = req("GET", f"https://billingbudgets.googleapis.com/v1/billingAccounts/{BILLING_ACC}/budgets")
budgets = d.get("budgets", [])
matching = [b for b in budgets if "286965080942" in str(b.get("budgetFilter", {}).get("projects", []))]
if matching:
    b = matching[0]
    amt = b['amount']['specifiedAmount']
    print(f"  {PASS} Budget: {amt['units']} {amt['currencyCode']}/月")
    thresholds = [r['thresholdPercent'] for r in b.get('thresholdRules', [])]
    print(f"     → thresholds: {thresholds}")
    pubsub = b.get('notificationsRule', {}).get('pubsubTopic')
    print(f"  {PASS if pubsub else WARN} Pub/Sub link: {pubsub or 'NOT LINKED'}")
else:
    print(f"  {FAIL} 予算が設定されていない！")


# ─── 2. API キー制限 ───
print("\n[2] API Key Restrictions ━━━━━━━━━━━━━━━━━━━━━")
s, d = req("GET", f"https://apikeys.googleapis.com/v2/projects/{PROJECT}/locations/global/keys")
gemini_keys = []
for k in d.get("keys", []):
    name = k.get("displayName", "")
    if "gemini" in name.lower() or "generative" in name.lower():
        gemini_keys.append(k)
        targets = k.get("restrictions", {}).get("apiTargets", [])
        services = [t.get("service") for t in targets]
        print(f"  Key: {name}")
        if "generativelanguage.googleapis.com" in services and len(services) == 1:
            print(f"  {PASS} restrictions.apiTargets = generativelanguage ONLY")
        else:
            print(f"  {FAIL} restrictions = {services}  (should be generativelanguage only!)")

        # browser/iOS/server restrictions
        if k.get("restrictions", {}).get("browserKeyRestrictions"):
            print(f"  {WARN} browserKeyRestrictions present (unusual for server key)")
        if not k.get("restrictions", {}).get("iosKeyRestrictions"):
            print(f"  {PASS} no iosKeyRestrictions (server-side use only)")
if not gemini_keys:
    print(f"  {FAIL} Gemini API キーが存在しない！")


# ─── 3. Quota override ───
print("\n[3] Generative Language API Quota ━━━━━━━━━━━━━")
metric = "generativelanguage.googleapis.com%2Fapi_requests"
limit = "%2Fmin%2Fproject%2Fregion"
s, d = req("GET", f"https://serviceusage.googleapis.com/v1beta1/projects/{PROJECT}/services/generativelanguage.googleapis.com/consumerQuotaMetrics/{metric}/limits/{limit}")
buckets = d.get("quotaBuckets", [])
override_found = False
for b in buckets:
    co = b.get("consumerOverride")
    if co:
        override_found = True
        print(f"  {PASS} consumerOverride = {co.get('overrideValue')} req/min")
        print(f"     defaultLimit={b.get('defaultLimit')}, effectiveLimit={b.get('effectiveLimit')}")
if not override_found:
    print(f"  {FAIL} consumerOverride 未設定！")


# ─── 4. Secret Manager versions ───
print("\n[4] Secret Manager (GEMINI_API_KEY) ━━━━━━━━━━━━")
s, d = req("GET", f"https://secretmanager.googleapis.com/v1/projects/{PROJECT}/secrets/GEMINI_API_KEY/versions")
v_states = {}
for v in d.get("versions", []):
    vid = v["name"].split("/")[-1]
    v_states[vid] = v.get("state")
print(f"  versions: {v_states}")
if v_states.get("1") == "DISABLED":
    print(f"  {PASS} v1 (漏洩キー) DISABLED")
else:
    print(f"  {FAIL} v1 が DISABLED ではない！state={v_states.get('1')}")
enabled_versions = [v for v, s in v_states.items() if s == "ENABLED"]
print(f"  {PASS if len(enabled_versions)==1 else WARN} ENABLED versions: {enabled_versions} (1個が望ましい)")


# ─── 5. Cloud Functions 状態 ───
print("\n[5] Cloud Functions ━━━━━━━━━━━━━━━━━━━━━━━━━━━")
s, d = req("GET", f"https://cloudfunctions.googleapis.com/v2/projects/{PROJECT}/locations/asia-northeast1/functions")
expected = {"aiGenerateWish", "cleanupExpiredPosts", "sakuraSeeder", "budgetAlert"}
found = set()
for fn in d.get("functions", []):
    fname = fn["name"].split("/")[-1]
    found.add(fname)
    state = fn.get("state")
    sc = fn.get("serviceConfig", {})
    max_inst = sc.get("maxInstanceCount")
    mem = sc.get("availableMemory")
    conc = sc.get("maxInstanceRequestConcurrency", "?")
    timeout_s = sc.get("timeoutSeconds")
    secrets = [s.get("key") for s in sc.get("secretEnvironmentVariables", [])]
    print(f"  {PASS if state == 'ACTIVE' else FAIL} {fname}: state={state}")
    print(f"     maxInstances={max_inst}, concurrency={conc}, memory={mem}, timeout={timeout_s}s, secrets={secrets}")

missing = expected - found
if missing:
    print(f"  {FAIL} 不足 functions: {missing}")
else:
    print(f"  {PASS} 期待される 4 functions すべて稼働中")


# ─── 6. Firestore rules ───
print("\n[6] Firestore Security Rules ━━━━━━━━━━━━━━━━━━")
s, d = req("GET", f"https://firebaserules.googleapis.com/v1/projects/{PROJECT}/releases")
firestore_release = None
for rel in d.get("releases", []):
    if "cloud.firestore" in rel.get("name", ""):
        firestore_release = rel
        break
if firestore_release:
    ruleset = firestore_release.get("rulesetName", "")
    print(f"  {PASS} ruleset deployed: {ruleset.split('/')[-1]}")
    s, d = req("GET", f"https://firebaserules.googleapis.com/v1/{ruleset}")
    src = d.get("source", {}).get("files", [{}])[0].get("content", "")
    checks = [
        ("system/{docId} で write: false", "allow write: if false" in src and "system" in src),
        ("text サイズ <=100 制限", "text.size() <= 100" in src),
        ("expireAt < 25h制限", "duration.value(25" in src),
        ("delete 全禁止", "allow delete: if false" in src),
        ("matched users/{uid}", "match /users/{uid}" in src),
    ]
    for name, ok in checks:
        print(f"     {PASS if ok else FAIL} {name}")
else:
    print(f"  {FAIL} Firestore rules がデプロイされていない！")


# ─── 7. Pub/Sub IAM ───
print("\n[7] Pub/Sub Topic IAM ━━━━━━━━━━━━━━━━━━━━━━━━")
s, d = req("POST", f"https://pubsub.googleapis.com/v1/projects/{PROJECT}/topics/kotodama-budget-alerts:getIamPolicy")
billing_publisher = False
for binding in d.get("bindings", []):
    if binding["role"] == "roles/pubsub.publisher":
        for m in binding["members"]:
            if "billing-budget-alert" in m:
                billing_publisher = True
                print(f"  {PASS} {m} → publisher")
if not billing_publisher:
    print(f"  {FAIL} Cloud Billing publisher 権限なし！")


# ─── 8. App Check ───
print("\n[8] App Check Configuration ━━━━━━━━━━━━━━━━━━")
APP_ID = "1:286965080942:ios:8a12e97651f88d6efa577f"
s, d = req("GET", f"https://firebaseappcheck.googleapis.com/v1/projects/{PROJECT}/apps/{APP_ID}/appAttestConfig")
if s == 200:
    print(f"  {PASS} AppAttest configured: tokenTtl={d.get('tokenTtl')}")
else:
    print(f"  {FAIL} AppAttest config not found ({s})")

for svc in ["firestore.googleapis.com", "firebasestorage.googleapis.com", "identitytoolkit.googleapis.com"]:
    s, d = req("GET", f"https://firebaseappcheck.googleapis.com/v1/projects/{PROJECT}/services/{svc}")
    mode = d.get("enforcementMode", "(none)")
    print(f"  {svc}: enforcementMode={mode}")


# ─── 9. system/aiRuntime + aiBudgetAlert 状態 ───
print("\n[9] Firestore system/* documents ━━━━━━━━━━━━━━")
for doc in ["aiRuntime", "aiBudgetAlert"]:
    s, d = req("GET", f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents/system/{doc}")
    if s == 200:
        fields = d.get("fields", {})
        print(f"  {PASS} system/{doc}:")
        for k, v in fields.items():
            val = next(iter(v.values()))
            if isinstance(val, str) and len(val) > 60:
                val = val[:60] + "..."
            print(f"     {k} = {val}")
    else:
        print(f"  {FAIL} system/{doc} 不在！")


# ─── 10. Service usage / API enabled ───
print("\n[10] Required APIs Enabled ━━━━━━━━━━━━━━━━━━━━")
required_apis = [
    "firestore.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "pubsub.googleapis.com",
    "billingbudgets.googleapis.com",
    "apikeys.googleapis.com",
    "firebaseappcheck.googleapis.com",
    "generativelanguage.googleapis.com",
]
for api in required_apis:
    s, d = req("GET", f"https://serviceusage.googleapis.com/v1/projects/{PROJECT}/services/{api}")
    state = d.get("state")
    icon = PASS if state == "ENABLED" else FAIL
    print(f"  {icon} {api}: {state}")


# ─── 11. Cloud Run service IAM (Functions Gen2) — public invoker チェック ───
print("\n[11] Cloud Run Service Invoker IAM ━━━━━━━━━━━━")
for fn in ["aigeneratewish", "cleanupexpiredposts", "sakuraseeder", "budgetalert"]:
    s, d = req("POST", f"https://asia-northeast1-run.googleapis.com/v2/projects/{PROJECT}/locations/asia-northeast1/services/{fn}:getIamPolicy")
    invoker_members = []
    for b in d.get("bindings", []):
        if b["role"] == "roles/run.invoker":
            invoker_members = b["members"]
    public = "allUsers" in invoker_members
    has_public = PASS if not public else WARN
    print(f"  {has_public} {fn}: invokers={invoker_members or 'EMPTY (auth-only)'}")
    if public:
        print(f"     → allUsers が invoker に含まれる (onCall は token 検証あり、pubsub は IAM)")


print("\n" + "=" * 70)
print("✅ 監査完了")
print("=" * 70)
