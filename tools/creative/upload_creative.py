import sys, time, json; sys.path.insert(0, "tools/asc"); from asc import *
root = sys.argv[1]
for lang in ("en", "zh"):
    for name in ("header_21x9", "search_3x2"):
        f = f"{root}/{lang}/{name}.png"; fn = f"creative_{lang}_{name}.png"
        import shutil, tempfile; tmp = tempfile.mkdtemp() + "/" + fn; shutil.copy(f, tmp)
        for attempt in (1, 2):
            try:
                rid = upload_asset("/v1/appAssetLibraryImages", "appAssetLibraries", "assetLibrary", "6832182341", tmp,
                                   {"category": "CREATIVE_ASSETS"}, timeout=60)
                time.sleep(3); a = req("GET", f"/v1/appAssetLibraryImages/{rid}")["data"]["attributes"]
                print(fn, rid, a.get("state"), a.get("stateDetails")); break
            except Exception as e:
                print(fn, "attempt", attempt, "ERR", str(e)[:500])
