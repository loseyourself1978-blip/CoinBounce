import sys, json; sys.path.insert(0, __file__.rsplit("/",1)[0]); from asc import *
V = sys.argv[1] if len(sys.argv)>1 else "58f301ae-8290-48e4-b0d3-f40412c2fb26"
for loc in get_all(f"/v1/appStoreVersions/{V}/appStoreVersionLocalizations"):
    print("LOC", loc["attributes"]["locale"], loc["id"])
    for s in get_all(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets"):
        print("  SET", s["attributes"]["screenshotDisplayType"], s["id"])
        for a in get_all(f"/v1/appScreenshotSets/{s['id']}/appScreenshots"):
            at=a["attributes"]; print("    SHOT", a["id"], at.get("fileName"), (at.get("assetDeliveryState") or {}).get("state"), (at.get("assetDeliveryState") or {}).get("errors"))
    for s in get_all(f"/v1/appStoreVersionLocalizations/{loc['id']}/appPreviewSets"):
        print("  PSET", s["attributes"]["previewType"], s["id"])
        for a in get_all(f"/v1/appPreviewSets/{s['id']}/appPreviews"):
            at=a["attributes"]; print("    PREV", a["id"], at.get("fileName"), (at.get("assetDeliveryState") or {}).get("state"))
