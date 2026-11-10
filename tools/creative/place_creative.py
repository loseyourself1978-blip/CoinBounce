import sys, json; sys.path.insert(0, "tools/asc"); from asc import *
LOCS = {"en": "b77f0628-9f38-46c8-966d-183ef4322459", "zh": "3577eccf-e188-4a86-b758-adb50f76036b"}
TYPES = {"header_21x9": "PRODUCT_PAGE_HEADER_ASSET", "search_3x2": "APP_STORE_SEARCH_RESULTS_ASSET"}
imgs = {i["attributes"]["fileName"]: i for i in get_all("/v1/appAssetLibraries/6832182341/images") if i["attributes"]["category"] == "CREATIVE_ASSETS"}
for lang, loc in LOCS.items():
    existing = {p["attributes"]["placementType"] for p in get_all(f"/v1/appStoreVersionLocalizations/{loc}/placements")}
    for name, pt in TYPES.items():
        fn = f"creative_{lang}_{name}.png"; img = imgs.get(fn)
        if not img: print(fn, "not in library"); continue
        if pt in existing: print(lang, pt, "already placed"); continue
        try:
            p = req("POST", "/v1/appAssetLibraryPlacements", {"data": {"type": "appAssetLibraryPlacements", "attributes": {"placementType": pt},
                "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc}},
                                  "image": {"data": {"type": "appAssetLibraryImages", "id": img["id"]}}}}})["data"]
            print(lang, pt, p["id"], p["attributes"].get("state"), p["attributes"].get("stateDetails"))
        except Exception as e: print(lang, pt, "ERR", str(e)[:700])
for lang, loc in LOCS.items():
    for p in get_all(f"/v1/appStoreVersionLocalizations/{loc}/placements"):
        a = p["attributes"]
        if a["placementType"] != "APP_SCREENSHOT": print("READBACK", lang, a["placementType"], a.get("placementGroup"), a["state"], a.get("stateDetails"))
