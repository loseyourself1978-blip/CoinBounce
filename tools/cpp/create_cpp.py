import sys, json, time; sys.path.insert(0, "tools/asc"); from asc import *
APP = "6832182341"; ROOT = sys.argv[1]
PROMO = {"en-US": "Satisfying 3D coin physics: push the pile and watch every coin pour over the edge. No sign-up, play offline.",
         "zh-Hans": "爽快的 3D 金币物理：推平金币堆，看每一枚金币哗哗落下。免注册，可离线畅玩。"}
existing = [p for p in get_all(f"/v1/apps/{APP}/appCustomProductPages") if p["attributes"]["name"] == "Satisfying Physics"]
if existing:
    page = existing[0]; print("CPP exists", page["id"])
else:
    body = {"data": {"type": "appCustomProductPages", "attributes": {"name": "Satisfying Physics"},
                     "relationships": {"app": {"data": {"type": "apps", "id": APP}},
                                       "appCustomProductPageVersions": {"data": [{"type": "appCustomProductPageVersions", "id": "${v1}"}]}}},
            "included": [{"type": "appCustomProductPageVersions", "id": "${v1}",
                          "relationships": {"appCustomProductPageLocalizations": {"data": [{"type": "appCustomProductPageLocalizations", "id": "${l1}"}, {"type": "appCustomProductPageLocalizations", "id": "${l2}"}]}}},
                         {"type": "appCustomProductPageLocalizations", "id": "${l1}", "attributes": {"locale": "en-US", "promotionalText": PROMO["en-US"]}},
                         {"type": "appCustomProductPageLocalizations", "id": "${l2}", "attributes": {"locale": "zh-Hans", "promotionalText": PROMO["zh-Hans"]}}]}
    page = req("POST", "/v1/appCustomProductPages", body)["data"]; print("CPP created", page["id"], page["attributes"])
print("visible:", page["attributes"].get("visible"))
vers = get_all(f"/v1/appCustomProductPages/{page['id']}/appCustomProductPageVersions")
for v in vers: print("VER", v["id"], v["attributes"])
v = vers[0]
for loc in get_all(f"/v1/appCustomProductPageVersions/{v['id']}/appCustomProductPageLocalizations"):
    lc = loc["attributes"]["locale"]; print("LOC", lc, loc["id"], loc["attributes"].get("promotionalText"))
    if loc["attributes"].get("promotionalText") != PROMO.get(lc):
        req("PATCH", f"/v1/appCustomProductPageLocalizations/{loc['id']}", {"data": {"type": "appCustomProductPageLocalizations", "id": loc["id"], "attributes": {"promotionalText": PROMO[lc]}}})
    sets = get_all(f"/v1/appCustomProductPageLocalizations/{loc['id']}/appScreenshotSets")
    s = next((x for x in sets if x["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67"), None)
    if not s:
        s = req("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"},
              "relationships": {"appCustomProductPageLocalization": {"data": {"type": "appCustomProductPageLocalizations", "id": loc["id"]}}}}})["data"]
    have = {a["attributes"]["fileName"]: (a["attributes"].get("assetDeliveryState") or {}).get("state") for a in get_all(f"/v1/appScreenshotSets/{s['id']}/appScreenshots")}
    d = "en" if lc == "en-US" else "zh"
    for i in range(1, 6):
        fn = f"cpp_{d}_0{i}.png"
        if have.get(fn) == "COMPLETE": print(" ", fn, "already COMPLETE"); continue
        import shutil, tempfile; tmp = tempfile.mkdtemp() + "/" + fn; shutil.copy(f"{ROOT}/{d}/0{i}.png", tmp)
        for attempt in (1, 2):
            try:
                rid = upload_asset("/v1/appScreenshots", "appScreenshotSets", "appScreenshotSet", s["id"], tmp, timeout=60)
                st = None
                for _ in range(20):
                    time.sleep(3); st = (req("GET", f"/v1/appScreenshots/{rid}")["data"]["attributes"].get("assetDeliveryState") or {}).get("state")
                    if st in ("COMPLETE", "FAILED"): break
                print(" ", fn, rid, st); break
            except Exception as e: print(" ", fn, "attempt", attempt, "ERR", str(e)[:400])
