#!/usr/bin/env python3
"""Google Play Developer API で v1.3.0 の H2 / H9 / H10 / 掲載文を実行する補助スクリプト。

前提: サービスアカウント JSON のパスを環境変数 PLAY_SA_JSON で渡す (内容は一切出力しない)。
      Play Console → ユーザーと権限 でそのサービスアカウントに「アプリ情報の表示」
      「注文と定期購入の管理」「リリース管理」を付与しておく。
      pip: google-api-python-client google-auth

使い方:
  python3 tool/play_api.py status            # トラック・定期購入・掲載言語の現況
  python3 tool/play_api.py create-subs       # H2: mrw.plus.monthly / yearly + trial-7d を作成・有効化
  python3 tool/play_api.py listings          # 掲載文 (.play-texts) を 4 言語で更新 (D6 是正版)
  python3 tool/play_api.py upload AAB [--notes]   # H9: 内部テストへ AAB をアップロード
  python3 tool/play_api.py promote VERSION_CODE [--fraction 0.2]   # H10: 製品版へ段階公開
  python3 tool/play_api.py rollout VERSION_CODE --fraction 0.5|1.0 # 段階公開の割合変更 / 100% で完了
  各コマンドは --dry-run で送信内容だけ表示する (認証しない)。
"""
from __future__ import annotations

import argparse
import io
import json
import os
import re
import sys

PKG = "com.teciora.moodringweather"
REGIONS_VERSION = "2022/02"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# --- 価格 (docs/pricing-decision.md §2 / release-plan-billing §5 Step 2。現地ロック) ---
EURO = ["AT", "BE", "CY", "DE", "EE", "ES", "FI", "FR", "GR", "HR", "IE", "IT",
        "LT", "LU", "LV", "MT", "NL", "PT", "SI", "SK"]


def money(cur: str, units: int, nanos: int = 0) -> dict:
    return {"currencyCode": cur, "units": str(units), "nanos": nanos}


PRICES = {
    "monthly": {"JP": money("JPY", 600), "US": money("USD", 4, 990_000_000),
                "MX": money("MXN", 69), "TW": money("TWD", 150), "HK": money("HKD", 38),
                **{c: money("EUR", 4, 990_000_000) for c in EURO}},
    "yearly": {"JP": money("JPY", 3000), "US": money("USD", 24, 990_000_000),
               "MX": money("MXN", 399), "TW": money("TWD", 790), "HK": money("HKD", 188),
               **{c: money("EUR", 29, 990_000_000) for c in EURO}},
}
OTHER = {
    "monthly": {"usdPrice": money("USD", 4, 990_000_000), "eurPrice": money("EUR", 4, 990_000_000)},
    "yearly": {"usdPrice": money("USD", 24, 990_000_000), "eurPrice": money("EUR", 29, 990_000_000)},
}

# --- 掲載 (D7: 特典は多地点のみ) ---
LISTINGS = {
    "monthly": [
        ("en-US", "Mood-Ring Weather Plus (Monthly)", "Keep an eye on up to 5 places at once.", ["Up to 5 places"]),
        ("ja-JP", "Mood-Ring Weather Plus（月額）", "最大5地点を、まとめて見られます。", ["最大5地点"]),
        ("es-ES", "Mood-Ring Weather Plus (Mensual)", "Sigue hasta 5 lugares a la vez.", ["Hasta 5 lugares"]),
        ("zh-CN", "Mood-Ring Weather Plus（月付）", "同时关注最多 5 个地点。", ["最多 5 个地点"]),
    ],
    "yearly": [
        ("en-US", "Mood-Ring Weather Plus (Yearly)", "Keep an eye on up to 5 places at once.", ["Up to 5 places"]),
        ("ja-JP", "Mood-Ring Weather Plus（年額）", "最大5地点を、まとめて見られます。", ["最大5地点"]),
        ("es-ES", "Mood-Ring Weather Plus (Anual)", "Sigue hasta 5 lugares a la vez.", ["Hasta 5 lugares"]),
        ("zh-CN", "Mood-Ring Weather Plus（年付）", "同时关注最多 5 个地点。", ["最多 5 个地点"]),
    ],
}
PRODUCTS = {"monthly": ("mrw.plus.monthly", "monthly-auto", "P1M"),
            "yearly": ("mrw.plus.yearly", "annual-auto", "P1Y")}
STORE_LANGS = {"en": "en-US", "ja": "ja-JP", "es": "es-ES", "zh": "zh-CN"}


def service():
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    path = os.environ.get("PLAY_SA_JSON")
    if not path or not os.path.isfile(path):
        sys.exit("PLAY_SA_JSON にサービスアカウント JSON のパスを設定してください")
    creds = service_account.Credentials.from_service_account_file(
        path, scopes=["https://www.googleapis.com/auth/androidpublisher"])
    return build("androidpublisher", "v3", credentials=creds, cache_discovery=False)


def sub_body(kind: str) -> dict:
    product_id, base_plan_id, period = PRODUCTS[kind]
    return {
        "packageName": PKG,
        "productId": product_id,
        "listings": [{"languageCode": lc, "title": t, "description": d, "benefits": b}
                     for lc, t, d, b in LISTINGS[kind]],
        "basePlans": [{
            "basePlanId": base_plan_id,
            "autoRenewingBasePlanType": {
                "billingPeriodDuration": period,
                "gracePeriodDuration": "P7D",
                "accountHoldDuration": "P30D",
                "resubscribeState": "RESUBSCRIBE_STATE_ACTIVE",
                "prorationMode": "SUBSCRIPTION_PRORATION_MODE_CHARGE_ON_NEXT_BILLING_DATE",
                "legacyCompatible": False,
            },
            "regionalConfigs": [{"regionCode": rc, "newSubscriberAvailability": True, "price": p}
                                for rc, p in PRICES[kind].items()],
            "otherRegionsConfig": {**OTHER[kind], "newSubscriberAvailability": True},
        }],
    }


def offer_body(kind: str) -> dict:
    product_id, base_plan_id, _ = PRODUCTS[kind]
    regions = list(PRICES[kind].keys())
    return {
        "packageName": PKG, "productId": product_id, "basePlanId": base_plan_id,
        "offerId": "trial-7d",
        "targeting": {"acquisitionRule": {"scope": {"specificSubscriptionInApp": product_id}}},
        "phases": [{"duration": "P7D",
                    "regionalConfigs": [{"regionCode": rc, "free": {}} for rc in regions],
                    "otherRegionsConfig": {"free": {}}}],
        "regionalConfigs": [{"regionCode": rc, "newSubscriberAvailability": True} for rc in regions],
        "otherRegionsConfig": {"newSubscriberAvailability": True},
    }


def cmd_status(svc, args):
    edit = svc.edits().insert(packageName=PKG, body={}).execute()
    eid = edit["id"]
    for t in svc.edits().tracks().list(packageName=PKG, editId=eid).execute().get("tracks", []):
        print("track", t["track"], [(r.get("status"), r.get("versionCodes"), r.get("userFraction"))
                                    for r in t.get("releases", [])])
    ls = svc.edits().listings().list(packageName=PKG, editId=eid).execute().get("listings", [])
    print("listing languages:", [l["language"] for l in ls])
    svc.edits().delete(packageName=PKG, editId=eid).execute()
    subs = svc.monetization().subscriptions().list(packageName=PKG).execute().get("subscriptions", [])
    for s in subs:
        print("subscription", s["productId"],
              [(bp["basePlanId"], bp.get("state"), [o.get("offerId") for o in bp.get("offers", [])])
               for bp in s.get("basePlans", [])])
    if not subs:
        print("subscriptions: (none)")


def _exists(err: Exception) -> bool:
    text = str(err)
    return "already exists" in text or "409" in text


def cmd_create_subs(svc, args):
    for kind in ("monthly", "yearly"):
        product_id, base_plan_id, _ = PRODUCTS[kind]
        body = sub_body(kind)
        if args.dry_run:
            print(json.dumps(body, ensure_ascii=False, indent=1)[:1500], "...")
            print(json.dumps(offer_body(kind), ensure_ascii=False)[:600], "...")
            continue
        try:
            svc.monetization().subscriptions().create(
                packageName=PKG, productId=product_id, regionsVersion_version=REGIONS_VERSION,
                body=body).execute()
            print("created", product_id)
        except Exception as e:  # 既存なら続行
            if not _exists(e):
                raise
            print("exists", product_id)
        svc.monetization().subscriptions().basePlans().activate(
            packageName=PKG, productId=product_id, basePlanId=base_plan_id, body={}).execute()
        print("activated base plan", base_plan_id)
        try:
            svc.monetization().subscriptions().basePlans().offers().create(
                packageName=PKG, productId=product_id, basePlanId=base_plan_id, offerId="trial-7d",
                regionsVersion_version=REGIONS_VERSION, body=offer_body(kind)).execute()
            print("created offer trial-7d for", product_id)
        except Exception as e:
            if not _exists(e):
                raise
            print("offer exists", product_id)
        svc.monetization().subscriptions().basePlans().offers().activate(
            packageName=PKG, productId=product_id, basePlanId=base_plan_id, offerId="trial-7d",
            body={}).execute()
        print("activated offer trial-7d for", product_id)


def read_text(name: str) -> str:
    return io.open(os.path.join(ROOT, ".play-texts", name), encoding="utf-8").read().strip()


def cmd_listings(svc, args):
    eid = "dry" if args.dry_run else svc.edits().insert(packageName=PKG, body={}).execute()["id"]
    for short, lang in STORE_LANGS.items():
        body = {"language": lang, "title": read_text(f"{short}_name.txt"),
                "shortDescription": read_text(f"{short}_short.txt"),
                "fullDescription": read_text(f"{short}_full.txt")}
        assert len(body["title"]) <= 30 and len(body["shortDescription"]) <= 80 \
            and len(body["fullDescription"]) <= 4000, lang
        if args.dry_run:
            print(lang, "title", len(body["title"]), "short", len(body["shortDescription"]),
                  "full", len(body["fullDescription"]))
            continue
        svc.edits().listings().update(packageName=PKG, editId=eid, language=lang, body=body).execute()
        print("updated listing", lang)
    if not args.dry_run:
        svc.edits().commit(packageName=PKG, editId=eid).execute()
        print("committed")


def release_notes() -> list:
    """store-listings/whats-new-1.3.0.md の ```ブロック``` を言語ごとに拾う (500 字以内のみ)。"""
    notes = []
    path = os.path.join(ROOT, "store-listings", "whats-new-1.3.0.md")
    if not os.path.isfile(path):
        return notes
    text = io.open(path, encoding="utf-8").read()
    for short, lang in STORE_LANGS.items():
        m = re.search(r"##[^\n]*\b" + short + r"\b[^\n]*\n+```\n(.*?)\n```", text, re.S | re.I)
        if m and len(m.group(1).strip()) <= 500:
            notes.append({"language": lang, "text": m.group(1).strip()})
    return notes


def cmd_upload(svc, args):
    from googleapiclient.http import MediaFileUpload
    if not os.path.isfile(args.aab):
        sys.exit(f"AAB が見つかりません: {args.aab}")
    if args.dry_run:
        print("would upload", args.aab, os.path.getsize(args.aab), "bytes → internal;",
              "notes:", [n["language"] for n in release_notes()])
        return
    eid = svc.edits().insert(packageName=PKG, body={}).execute()["id"]
    media = MediaFileUpload(args.aab, mimetype="application/octet-stream", resumable=True)
    bundle = svc.edits().bundles().upload(packageName=PKG, editId=eid, media_body=media).execute()
    vc = bundle["versionCode"]
    print("uploaded versionCode", vc)
    release = {"versionCodes": [str(vc)], "status": "completed", "name": f"1.3.0 ({vc})"}
    if args.notes:
        release["releaseNotes"] = release_notes()
    svc.edits().tracks().update(packageName=PKG, editId=eid, track="internal",
                                body={"track": "internal", "releases": [release]}).execute()
    svc.edits().commit(packageName=PKG, editId=eid).execute()
    print("internal track updated and committed")


def set_production(svc, version_code: str, fraction: float, dry_run: bool):
    status = "completed" if fraction >= 1.0 else "inProgress"
    release = {"versionCodes": [str(version_code)], "status": status,
               "name": f"1.3.0 ({version_code})", "releaseNotes": release_notes()}
    if status == "inProgress":
        release["userFraction"] = fraction
    if dry_run:
        print("would set production:", json.dumps(release, ensure_ascii=False)[:600])
        return
    eid = svc.edits().insert(packageName=PKG, body={}).execute()["id"]
    svc.edits().tracks().update(packageName=PKG, editId=eid, track="production",
                                body={"track": "production", "releases": [release]}).execute()
    svc.edits().commit(packageName=PKG, editId=eid).execute()
    print(f"production: versionCode {version_code} status={status} fraction={fraction}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true")
    sp = ap.add_subparsers(dest="cmd", required=True)
    sp.add_parser("status")
    sp.add_parser("create-subs")
    sp.add_parser("listings")
    up = sp.add_parser("upload")
    up.add_argument("aab")
    up.add_argument("--notes", action="store_true")
    pr = sp.add_parser("promote")
    pr.add_argument("version_code")
    pr.add_argument("--fraction", type=float, default=0.2)
    ro = sp.add_parser("rollout")
    ro.add_argument("version_code")
    ro.add_argument("--fraction", type=float, required=True)
    args = ap.parse_args()
    svc = None if args.dry_run else service()
    if args.cmd == "status":
        cmd_status(svc, args)
    elif args.cmd == "create-subs":
        cmd_create_subs(svc, args)
    elif args.cmd == "listings":
        cmd_listings(svc, args)
    elif args.cmd == "upload":
        cmd_upload(svc, args)
    elif args.cmd == "promote":
        set_production(svc, args.version_code, args.fraction, args.dry_run)
    elif args.cmd == "rollout":
        set_production(svc, args.version_code, args.fraction, args.dry_run)


if __name__ == "__main__":
    main()
