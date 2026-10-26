import argparse
import json
import os
from datetime import datetime


def _h(s: str) -> str:
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&#39;")
    )


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--compare_json", required=True)
    p.add_argument("--out_html", required=True)
    p.add_argument("--title", default="CoinBounce Acceptance Report")
    p.add_argument("--version", default="")
    p.add_argument("--commit", default="")
    args = p.parse_args()

    with open(args.compare_json, "r", encoding="utf-8") as f:
        data = json.load(f)

    out_dir = os.path.dirname(os.path.abspath(args.out_html))
    os.makedirs(out_dir, exist_ok=True)

    overall = data.get("overall", {})
    regions = data.get("regions", [])
    artifacts = data.get("artifacts", {})

    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    header_meta = f"生成时间：{_h(now)}"
    if args.version:
        header_meta += f" ｜ 版本：{_h(args.version)}"
    if args.commit:
        header_meta += f" ｜ Commit：{_h(args.commit)}"

    def img(src: str, w: int = 220) -> str:
        return f'<img src="{_h(src)}" style="max-width:{w}px;border-radius:8px;border:1px solid #333;" />'

    rows = []
    for r in regions:
        rows.append(
            f"""
            <div class="card">
              <div class="card-title">{_h(r.get("label", r.get("id","")))}</div>
              <div class="metrics">
                <div><b>MAE</b> {r.get("mae"):.2f}</div>
                <div><b>RMSE</b> {r.get("rmse"):.2f}</div>
                <div><b>PSNR</b> {r.get("psnr"):.2f}</div>
              </div>
              <div class="imgs">
                <div><div class="cap">参考</div>{img(r["artifacts"]["reference"])}</div>
                <div><div class="cap">当前</div>{img(r["artifacts"]["candidate"])}</div>
                <div><div class="cap">差异</div>{img(r["artifacts"]["diff"])}</div>
              </div>
            </div>
            """
        )

    html = f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{_h(args.title)}</title>
  <style>
    body {{ background:#0b0f14; color:#e6edf3; font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "PingFang SC", "Microsoft YaHei", Arial; margin:0; }}
    .wrap {{ max-width:1100px; margin:0 auto; padding:24px; }}
    .h1 {{ font-size:22px; font-weight:800; }}
    .meta {{ color:#9aa4af; margin-top:6px; font-size:13px; }}
    .top-grid {{ display:grid; grid-template-columns:1fr 1fr; gap:14px; margin-top:16px; }}
    .panel {{ background:#0f1620; border:1px solid #223041; border-radius:12px; padding:14px; }}
    .kvs {{ display:flex; gap:18px; flex-wrap:wrap; }}
    .kv b {{ display:block; font-size:12px; color:#9aa4af; font-weight:700; }}
    .kv span {{ font-size:20px; font-weight:800; }}
    .imgs {{ display:flex; gap:12px; align-items:flex-start; flex-wrap:wrap; }}
    .cap {{ font-size:12px; color:#9aa4af; margin:8px 0 6px; }}
    .grid {{ margin-top:16px; display:grid; grid-template-columns:1fr; gap:12px; }}
    .card {{ background:#0f1620; border:1px solid #223041; border-radius:12px; padding:14px; }}
    .card-title {{ font-weight:900; margin-bottom:10px; }}
    .metrics {{ display:flex; gap:16px; color:#c7d1db; font-size:13px; margin-bottom:10px; }}
    a {{ color:#7dd3fc; }}
  </style>
</head>
<body>
  <div class="wrap">
    <div class="h1">{_h(args.title)}</div>
    <div class="meta">{header_meta}</div>

    <div class="top-grid">
      <div class="panel">
        <div class="kvs">
          <div class="kv"><b>Overall MAE</b><span>{overall.get("mae", 0):.2f}</span></div>
          <div class="kv"><b>Overall RMSE</b><span>{overall.get("rmse", 0):.2f}</span></div>
          <div class="kv"><b>Overall PSNR</b><span>{overall.get("psnr", 0):.2f}</span></div>
        </div>
        <div class="meta" style="margin-top:10px;">
          参考图：{_h(os.path.basename(data.get("reference","")))} ｜ 当前截图：{_h(os.path.basename(data.get("candidate","")))}
        </div>
      </div>
      <div class="panel">
        <div class="imgs">
          <div><div class="cap">参考（适配后）</div>{img(artifacts.get("reference_fit",""))}</div>
          <div><div class="cap">当前（适配后）</div>{img(artifacts.get("candidate_fit",""))}</div>
        </div>
      </div>
    </div>

    <div class="grid">
      {''.join(rows)}
    </div>
  </div>
</body>
</html>
"""

    with open(args.out_html, "w", encoding="utf-8") as f:
        f.write(html)


if __name__ == "__main__":
    main()

