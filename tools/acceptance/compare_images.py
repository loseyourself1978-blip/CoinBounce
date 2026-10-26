import argparse
import json
import math
import os
from dataclasses import dataclass
from typing import Dict, List, Tuple

from PIL import Image, ImageChops, ImageStat


@dataclass(frozen=True)
class Region:
    id: str
    label: str
    box: Tuple[int, int, int, int]  # left, top, right, bottom


def _load_regions(path: str) -> Tuple[Tuple[int, int], List[Region], str]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    w, h = data["target_size"]
    regions = [
        Region(id=r["id"], label=r.get("label", r["id"]), box=tuple(r["box"]))
        for r in data["regions"]
    ]
    return (w, h), regions, data.get("name", os.path.basename(path))


def _load_and_fit(path: str, target_size: Tuple[int, int]) -> Image.Image:
    img = Image.open(path).convert("RGB")
    return img.resize(target_size, Image.Resampling.LANCZOS)


def _mae(a: Image.Image, b: Image.Image) -> float:
    diff = ImageChops.difference(a, b)
    stat = ImageStat.Stat(diff)
    # mean over channels, normalized 0..255
    mean = sum(stat.mean) / len(stat.mean)
    return float(mean)


def _rmse(a: Image.Image, b: Image.Image) -> float:
    diff = ImageChops.difference(a, b)
    stat = ImageStat.Stat(diff)
    # RMS per channel
    rms = sum(stat.rms) / len(stat.rms)
    return float(rms)


def _psnr(rmse: float, peak: float = 255.0) -> float:
    if rmse <= 1e-9:
        return 99.0
    return 20.0 * math.log10(peak / rmse)


def compare(reference: str, candidate: str, regions_path: str, out_dir: str) -> Dict:
    target_size, regions, name = _load_regions(regions_path)
    ref_img = _load_and_fit(reference, target_size)
    cand_img = _load_and_fit(candidate, target_size)

    os.makedirs(out_dir, exist_ok=True)
    ref_fit_path = os.path.join(out_dir, "reference_fit.png")
    cand_fit_path = os.path.join(out_dir, "candidate_fit.png")
    ref_img.save(ref_fit_path)
    cand_img.save(cand_fit_path)

    results = {
        "reference": os.path.abspath(reference),
        "candidate": os.path.abspath(candidate),
        "regions_file": os.path.abspath(regions_path),
        "profile": name,
        "target_size": list(target_size),
        "overall": {},
        "regions": [],
        "artifacts": {
            "reference_fit": os.path.basename(ref_fit_path),
            "candidate_fit": os.path.basename(cand_fit_path),
        },
    }

    overall_mae = _mae(ref_img, cand_img)
    overall_rmse = _rmse(ref_img, cand_img)
    results["overall"] = {
        "mae": overall_mae,
        "rmse": overall_rmse,
        "psnr": _psnr(overall_rmse),
    }

    for r in regions:
        ref_crop = ref_img.crop(r.box)
        cand_crop = cand_img.crop(r.box)
        region_mae = _mae(ref_crop, cand_crop)
        region_rmse = _rmse(ref_crop, cand_crop)
        diff = ImageChops.difference(ref_crop, cand_crop)

        ref_name = f"ref_{r.id}.png"
        cand_name = f"cand_{r.id}.png"
        diff_name = f"diff_{r.id}.png"

        ref_crop.save(os.path.join(out_dir, ref_name))
        cand_crop.save(os.path.join(out_dir, cand_name))
        diff.save(os.path.join(out_dir, diff_name))

        results["regions"].append(
            {
                "id": r.id,
                "label": r.label,
                "box": list(r.box),
                "mae": region_mae,
                "rmse": region_rmse,
                "psnr": _psnr(region_rmse),
                "artifacts": {
                    "reference": ref_name,
                    "candidate": cand_name,
                    "diff": diff_name,
                },
            }
        )

    return results


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--reference", required=True)
    p.add_argument("--candidate", required=True)
    p.add_argument("--regions", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--json", default=None)
    args = p.parse_args()

    res = compare(args.reference, args.candidate, args.regions, args.out)
    json_path = args.json or os.path.join(args.out, "compare.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(res, f, ensure_ascii=False, indent=2)
    print(json_path)


if __name__ == "__main__":
    main()

