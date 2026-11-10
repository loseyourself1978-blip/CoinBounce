#!/usr/bin/env python3
"""v11.8 store update for version 1.0.0 (58f301ae).
usage: release_v118.py screenshots|cpp|metadata|build <buildNumber>|status|submit"""
import os, shutil, sys, tempfile, time, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc import *

APP = "6832182341"
VERSION = "58f301ae-8290-48e4-b0d3-f40412c2fb26"
CPP = "6abf4431-6a42-43e4-b4a1-675d5c00ce27"
ROOT = os.path.expanduser("~/Downloads/CoinBounce_资料归档/上架截图_v118")
LOC_DIR = {"en-US": "en", "zh-Hans": "zh"}

def wait_complete(rid, tries=40):
    st = None
    for _ in range(tries):
        time.sleep(3)
        st = (req("GET", f"/v1/appScreenshots/{rid}")["data"]["attributes"].get("assetDeliveryState") or {}).get("state")
        if st in ("COMPLETE", "FAILED"): break
    return st

def replace_set(set_id, files, prefix):
    """delete every screenshot in the set, upload files in order (60 s timeout, one retry), read back"""
    for a in get_all(f"/v1/appScreenshotSets/{set_id}/appScreenshots"):
        req("DELETE", f"/v1/appScreenshots/{a['id']}")
    for i, f in enumerate(files, 1):
        tmp = os.path.join(tempfile.mkdtemp(), f"{prefix}_{i:02d}.png"); shutil.copy(f, tmp)
        for attempt in (1, 2):
            try:
                rid = upload_asset("/v1/appScreenshots", "appScreenshotSets", "appScreenshotSet", set_id, tmp, timeout=60)
                print(" ", os.path.basename(tmp), rid, wait_complete(rid)); break
            except Exception as e:
                print(" ", os.path.basename(tmp), "attempt", attempt, "ERR", str(e)[:300])
    got = [(a["attributes"]["fileName"], (a["attributes"].get("assetDeliveryState") or {}).get("state")) for a in get_all(f"/v1/appScreenshotSets/{set_id}/appScreenshots")]
    print("  readback", got)

def sets_for(loc_path, rel):
    sets = get_all(f"{loc_path}/appScreenshotSets")
    s = next((x for x in sets if x["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67"), None)
    if not s:
        s = req("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": "APP_IPHONE_67"},
              "relationships": {rel: {"data": {"type": rel + "s", "id": loc_path.rsplit("/", 1)[-1]}}}}})["data"]
    return s["id"]

def screenshots():
    for loc in get_all(f"/v1/appStoreVersions/{VERSION}/appStoreVersionLocalizations"):
        lc = loc["attributes"]["locale"]; d = LOC_DIR[lc]
        print(lc)
        sid = sets_for(f"/v1/appStoreVersionLocalizations/{loc['id']}", "appStoreVersionLocalization")
        replace_set(sid, [f"{ROOT}/{d}/0{i}.png" for i in range(1, 6)], f"v118_{d}")

def cpp():
    for v in get_all(f"/v1/appCustomProductPages/{CPP}/appCustomProductPageVersions"):
        for loc in get_all(f"/v1/appCustomProductPageVersions/{v['id']}/appCustomProductPageLocalizations"):
            lc = loc["attributes"]["locale"]; d = LOC_DIR[lc]
            print("CPP", lc)
            sid = sets_for(f"/v1/appCustomProductPageLocalizations/{loc['id']}", "appCustomProductPageLocalization")
            replace_set(sid, [f"{ROOT}/cpp_physics/{d}/0{i}.png" for i in range(1, 6)], f"cpp118_{d}")
    print("CPP visible:", req("GET", f"/v1/appCustomProductPages/{CPP}")["data"]["attributes"]["visible"])

DESC_FIX = {
    "en-US": ("• Running low? Watch an optional video to top up your coins.",
              "• Tap ▶ +50 any time to watch an optional video for 50 coins (every 90 seconds, up to 10 a day)."),
    "zh-Hans": ("• 金币不够时，可以自愿观看视频补充金币。",
                "• 随时点 ▶ +50 自愿观看视频领 50 金币（每 90 秒一次，每天最多 10 次）。"),
}
NOTES_ADD = (" The ▶ +50 button at the top right of the balance is always available: it plays an optional rewarded video"
             " (Google AdMob) for 50 virtual coins, once every 90 seconds, up to 10 times a day.")

def metadata():
    for loc in get_all(f"/v1/appStoreVersions/{VERSION}/appStoreVersionLocalizations"):
        a = loc["attributes"]; lc = a["locale"]; old, new = DESC_FIX[lc]
        desc = a["description"]
        if old in desc:
            desc = desc.replace(old, new)
            req("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": {"description": desc}}})
        print(lc, "description ok:", new in req("GET", f"/v1/appStoreVersionLocalizations/{loc['id']}")["data"]["attributes"]["description"])
    rd = req("GET", f"/v1/appStoreVersions/{VERSION}/appStoreReviewDetail")["data"]
    notes = rd["attributes"]["notes"] or ""
    notes = notes.replace("When players run low, they can choose to watch a rewarded video ad (Google AdMob) for more coins.", "").replace("  ", " ").strip()
    if "▶ +50" not in notes:
        notes = notes + NOTES_ADD
        req("PATCH", f"/v1/appStoreReviewDetails/{rd['id']}", {"data": {"type": "appStoreReviewDetails", "id": rd["id"], "attributes": {"notes": notes}}})
    print("notes:", req("GET", f"/v1/appStoreReviewDetails/{rd['id']}")["data"]["attributes"]["notes"])

def build(number):
    b = None
    for _ in range(60):
        bs = get_all(f"/v1/builds", params={"filter[app]": APP, "filter[version]": number})
        if bs and bs[0]["attributes"]["processingState"] == "VALID": b = bs[0]; break
        print("build", number, bs[0]["attributes"]["processingState"] if bs else "not found yet"); time.sleep(30)
    if not b: print("build not VALID"); return
    req("PATCH", f"/v1/appStoreVersions/{VERSION}/relationships/build", {"data": {"type": "builds", "id": b["id"]}})
    v = req("GET", f"/v1/appStoreVersions/{VERSION}", params={"include": "build"})
    print("attached:", [(x["attributes"]["version"], x["attributes"]["processingState"]) for x in v.get("included", [])])

def status():
    v = req("GET", f"/v1/appStoreVersions/{VERSION}", params={"include": "build"})
    print("version", v["data"]["attributes"]["appStoreState"], [(x["attributes"]["version"], x["attributes"]["processingState"]) for x in v.get("included", [])])

def submit():
    sub = req("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
          "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})["data"]
    print("submission", sub["id"])
    req("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": VERSION}}}}})
    for v in get_all(f"/v1/appCustomProductPages/{CPP}/appCustomProductPageVersions"):
        try:
            req("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
                "appCustomProductPageVersion": {"data": {"type": "appCustomProductPageVersions", "id": v["id"]}}}}})
            print("CPP version added", v["id"])
        except Exception as e: print("CPP add ERR", str(e)[:600])
    r = req("PATCH", f"/v1/reviewSubmissions/{sub['id']}", {"data": {"type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})
    print("state:", r["data"]["attributes"].get("state"))

if __name__ == "__main__":
    cmd = sys.argv[1]
    {"screenshots": screenshots, "cpp": cpp, "metadata": metadata, "status": status, "submit": submit}.get(cmd, lambda: build(sys.argv[2]))()
