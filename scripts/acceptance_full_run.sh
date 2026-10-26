#!/usr/bin/env bash
set -euo pipefail

echo "[FULL-RUN] Starting local offline acceptance run..."

echo "Step 1/5: Generate refined scene references"
bash acceptance/generate_references.sh

echo "Step 2/5: Run offline acceptance (visual regression + basic checks)"
python3 acceptance/AcceptanceRunner.py acceptance/config.json || true

echo "Step 3/5: Assemble acceptance report (markdown)"
bash acceptance/assemble_report.sh

echo "Step 4/5: Pack offline acceptance package"
bash acceptance/pack.sh

echo "Step 5/5: Run Play on Simulator (if available)"
bash scripts/ios_sim_run.sh || true

echo "[FULL-RUN] Completed. Outputs in acceptance/ and the simulator run outputs above."
